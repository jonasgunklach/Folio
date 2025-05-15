// ContentView.swift
// CorePDF
//
// MIT License
// Copyright (c) 2026 CorePDF Contributors
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.

import SwiftUI
import UniformTypeIdentifiers

/// Root layout.
/// The native `.toolbar` items merge into the window chrome with Liquid Glass
/// on macOS 26. Tabs live in the `.principal` (title-bar center) slot,
/// exactly like Safari's URL/tab strip.
struct ContentView: View {

    @Environment(AppState.self) private var appState

    private var tab: DocumentTab? { appState.activeTab }
    private var hasDoc: Bool { tab != nil }

    var body: some View {
        HStack(spacing: 0) {
            // ── Thumbnail sidebar ──────────────────────────────────────
            if appState.isSidebarVisible, let tab {
                ThumbnailSidebarView(document: tab.document, activeTab: tab)
                    .frame(width: 200)
                    .transition(.move(edge: .leading).combined(with: .opacity))
                Divider()
            }

            // ── Main content area ──────────────────────────────────────
            Group {
                if let tab {
                    switch tab.viewMode {
                    case .scroll:
                        PDFViewerView(tab: tab)
                            .id(tab.id)
                    case .grid:
                        PageOrganizerView(tab: tab)
                            .id(tab.id)
                    }
                } else {
                    WelcomeView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.85), value: appState.isSidebarVisible)

        // ── Toolbar ────────────────────────────────────────────────────
        .toolbar {

            // ── Far-left: Sidebar toggle ───────────────────────────────
            ToolbarItem(placement: .navigation) {
                Button {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
                        appState.isSidebarVisible.toggle()
                    }
                } label: {
                    Image(systemName: appState.isSidebarVisible
                          ? "sidebar.left"
                          : "sidebar.left")
                        .symbolVariant(appState.isSidebarVisible ? .none : .slash)
                }
                .help(appState.isSidebarVisible ? "Hide Thumbnails (⌘⇧S)" : "Show Thumbnails (⌘⇧S)")
                .keyboardShortcut("s", modifiers: [.command, .shift])
            }

            // ── Left: Open + page navigation ──────────────────────────
            ToolbarItem(placement: .navigation) {
                Button {
                    appState.isFileImporterPresented = true
                } label: {
                    Label("Open PDF", systemImage: "folder.badge.plus")
                }
                .help("Open PDF (⌘O)")
            }

            ToolbarItem(placement: .navigation) {
                HStack(spacing: 2) {
                    Button {
                        guard let tab else { return }
                        tab.currentPageIndex = max(tab.currentPageIndex - 1, 0)
                    } label: { Image(systemName: "chevron.left") }
                    .disabled(!hasDoc)
                    .help("Previous Page")

                    Text(tab.map { "\($0.currentPageLabel) / \($0.pageCount)" } ?? "— / —")
                        .font(.system(size: 11, weight: .medium).monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 64)

                    Button {
                        guard let tab else { return }
                        tab.currentPageIndex = min(tab.currentPageIndex + 1, tab.pageCount - 1)
                    } label: { Image(systemName: "chevron.right") }
                    .disabled(!hasDoc)
                    .help("Next Page")
                }
            }

            // ── Centre: Tab strip (Safari-style) ──────────────────────
            ToolbarItem(placement: .principal) {
                DocumentTabBar()
                    .frame(minWidth: 300, maxWidth: .infinity)
            }

            // ── Right: View mode + tools + reading mode ────────────────
            ToolbarItem(placement: .primaryAction) {
                Picker("View", selection: Binding(
                    get: { tab?.viewMode ?? .scroll },
                    set: { tab?.viewMode = $0 }
                )) {
                    ForEach(ViewMode.allCases) { mode in
                        Image(systemName: mode.symbolName).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .fixedSize()
                .disabled(!hasDoc)
                .help("View Mode")
            }

            ToolbarItem(placement: .primaryAction) {
                // Zoom group (only relevant in scroll view)
                HStack(spacing: 0) {
                    Button { tab?.viewerViewModel.zoomOut() } label: {
                        Image(systemName: "minus")
                    }
                    .disabled(!hasDoc || tab?.viewMode == .grid)
                    .help("Zoom Out (⌘−)")

                    Button { tab?.viewerViewModel.zoomToFit() } label: {
                        Text(tab.map {
                            String(format: "%.0f%%", $0.viewerViewModel.scaleFactor * 100)
                        } ?? "—")
                        .font(.system(size: 11, weight: .medium).monospacedDigit())
                        .frame(minWidth: 44)
                    }
                    .disabled(!hasDoc || tab?.viewMode == .grid)
                    .help("Actual Size (⌘0)")

                    Button { tab?.viewerViewModel.zoomIn() } label: {
                        Image(systemName: "plus")
                    }
                    .disabled(!hasDoc || tab?.viewMode == .grid)
                    .help("Zoom In (⌘=)")
                }
            }

            ToolbarItem(placement: .primaryAction) {
                Picker("Tool", selection: Binding(
                    get: { appState.activeTool },
                    set: { if hasDoc { appState.activeTool = $0 } }
                )) {
                    ForEach(ActiveTool.allCases.filter(\.isPrimaryTool)) { tool in
                        Image(systemName: tool.symbolName).tag(tool)
                    }
                }
                .pickerStyle(.segmented)
                .fixedSize()
                .disabled(!hasDoc || tab?.viewMode == .grid)
                .help("Annotation Tools")
                // Hidden buttons capture per-tool keyboard shortcuts
                .background {
                    Group {
                        Button("") { if hasDoc { appState.activeTool = .select }    }.keyboardShortcut("e", modifiers: [])
                        Button("") { if hasDoc { appState.activeTool = .highlight } }.keyboardShortcut("h", modifiers: [])
                        Button("") { if hasDoc { appState.activeTool = .underline } }.keyboardShortcut("u", modifiers: [])
                        Button("") { if hasDoc { appState.activeTool = .strikethrough } }.keyboardShortcut("k", modifiers: [])
                        Button("") { if hasDoc { appState.activeTool = .freehand } }.keyboardShortcut("f", modifiers: [])
                        Button("") { if hasDoc { appState.activeTool = .text } }.keyboardShortcut("t", modifiers: [])
                    }
                    .opacity(0).frame(width: 0, height: 0).allowsHitTesting(false)
                }
            }

            ToolbarItem(placement: .primaryAction) {
                Menu {
                    ForEach(ReadingMode.allCases) { mode in
                        Button {
                            tab?.readingMode = mode
                        } label: {
                            Label(mode.rawValue, systemImage: mode.symbolName)
                        }
                    }
                } label: {
                    Image(systemName: tab?.readingMode.symbolName ?? "sun.max")
                        .symbolRenderingMode(.multicolor)
                }
                .disabled(!hasDoc)
                .help("Reading Mode")
            }
        }
        .fileImporter(
            isPresented: Binding(
                get: { appState.isFileImporterPresented },
                set: { appState.isFileImporterPresented = $0 }
            ),
            allowedContentTypes: [UTType.pdf],
            allowsMultipleSelection: true
        ) { result in
            if case .success(let urls) = result {
                urls.forEach { appState.openDocument(at: $0) }
            }
        }
        // ── Unsaved-changes alert ──────────────────────────────────────
        .alert("Save Changes?",
               isPresented: Binding(
                get: { appState.tabPendingClose != nil },
                set: { if !$0 { appState.tabPendingClose = nil } }
               )
        ) {
            Button("Save") {
                let tab = appState.tabPendingClose
                let id = tab?.id
                Task {
                    await tab?.save()
                    if let id { appState.performCloseTab(id) }
                }
            }
            Button("Don't Save", role: .destructive) {
                if let id = appState.tabPendingClose?.id { appState.performCloseTab(id) }
            }
            Button("Cancel", role: .cancel) { appState.tabPendingClose = nil }
        } message: {
            if let t = appState.tabPendingClose {
                Text("\"\(t.title)\" has unsaved changes. Save before closing?")
            }
        }
    }
}

