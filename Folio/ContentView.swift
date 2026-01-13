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
    @Environment(SettingsStore.self) private var settings

    private var tab: DocumentTab? { appState.activeTab }
    private var hasDoc: Bool { tab != nil }

    /// Persisted sidebar width, clamped to [120, 400]
    @State private var sidebarWidth: CGFloat = 180
    @State private var aiSidebarWidth: CGFloat = 280

    var body: some View {
        HStack(spacing: 0) {
            // ── Thumbnail sidebar ──────────────────────────────────────
            if appState.isSidebarVisible, let tab {
                ThumbnailSidebarView(document: tab.document, activeTab: tab,
                                     isInteractive: tab.viewMode == .scroll)
                    .frame(width: sidebarWidth)
                    .transition(.move(edge: .leading).combined(with: .opacity))

                // Drag handle
                SidebarResizeHandle(width: $sidebarWidth)
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

            // ── AI sidebar (right) ─────────────────────────────────────
            if appState.isAISidebarVisible {
                SidebarResizeHandle(width: $aiSidebarWidth, flipped: true)

                AIChatSidebarView(document: tab?.document)
                    .frame(width: aiSidebarWidth)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        // ── Hidden keyboard shortcuts for annotation tools ────────────
        // Kept in the view body (not in the toolbar) so they don't pollute
        // the toolbar overflow menu item labels.
        .background {
            Group {
                Button("") { if hasDoc { appState.activeTool = .select }        }.keyboardShortcut("e", modifiers: [])
                Button("") { if hasDoc { appState.activeTool = .highlight }     }.keyboardShortcut("h", modifiers: [])
                Button("") { if hasDoc { appState.activeTool = .underline }     }.keyboardShortcut("u", modifiers: [])
                Button("") { if hasDoc { appState.activeTool = .strikethrough } }.keyboardShortcut("k", modifiers: [])
                Button("") { if hasDoc { appState.activeTool = .text }          }.keyboardShortcut("c", modifiers: [])
                Button("") { if hasDoc { appState.activeTool = .signature }     }.keyboardShortcut("g", modifiers: [])
            }
            .opacity(0).frame(width: 0, height: 0).allowsHitTesting(false)
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.85), value: appState.isSidebarVisible)
        .animation(.spring(response: 0.32, dampingFraction: 0.85), value: appState.isAISidebarVisible)
        // ── Tab bar row (pinned below toolbar when style == .bar) ─────
        .safeAreaInset(edge: .top, spacing: 0) {
            if settings.tabBarStyle == .bar {
                VStack(spacing: 0) {
                    TabBarRowView()
                    Divider()
                }
            }
        }

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

            // ── Left: page navigation ────────────────────────────
            ToolbarItem(placement: .navigation) {
                HStack(spacing: 0) {
                    Button {
                        guard let tab else { return }
                        tab.currentPageIndex = max(tab.currentPageIndex - 1, 0)
                    } label: {
                        Image(systemName: "chevron.left")
                            .frame(width: 20, height: 22)
                    }
                    .disabled(!hasDoc)
                    .help("Previous Page")

                    Text(tab.map { "\($0.currentPageLabel) / \($0.pageCount)" } ?? "— / —")
                        .font(.system(size: 11, weight: .medium).monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 42, alignment: .center)

                    Button {
                        guard let tab else { return }
                        tab.currentPageIndex = min(tab.currentPageIndex + 1, tab.pageCount - 1)
                    } label: {
                        Image(systemName: "chevron.right")
                            .frame(width: 20, height: 22)
                    }
                    .disabled(!hasDoc)
                    .help("Next Page")
                }
            }

            // ── Left: view mode (scroll / grid) ───────────────────────
            ToolbarItem(placement: .navigation) {
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

            // ── Centre: Tab strip (toolbar style) or invisible anchor (.bar style)
            ToolbarItem(placement: .principal) {
                if settings.tabBarStyle == .toolbar {
                    DocumentTabBar()
                        .frame(minWidth: 300, maxWidth: .infinity)
                } else {
                    // Full-width clear view preserves the three-zone layout
                    // (nav left / primary right) without visible separator lines.
                    Color.clear.frame(minWidth: 100, maxWidth: .infinity)
                }
            }

            // ── Right group 1: Annotation tools ───────────────────────
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
            }

            // ── Right group 2: Zoom ───────────────────────────────────
            // ── Right group 2: Zoom ────────────────────────────────────────────
            // Menu collapses to a proper "Zoom" submenu in overflow, matching
            // the reading-mode pattern. Shows current scale in the label.
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button { tab?.viewerViewModel.zoomIn() } label: {
                        Label("Zoom In", systemImage: "plus.magnifyingglass")
                    }
                    Button { tab?.viewerViewModel.zoomOut() } label: {
                        Label("Zoom Out", systemImage: "minus.magnifyingglass")
                    }
                    Divider()
                    Button { tab?.viewerViewModel.zoomToFit() } label: {
                        Label("Actual Size", systemImage: "1.magnifyingglass")
                    }
                } label: {
                    Label(
                        tab.map { String(format: "%.0f%%", $0.viewerViewModel.scaleFactor * 100) } ?? "Zoom",
                        systemImage: "magnifyingglass"
                    )
                    .labelStyle(.iconOnly)
                }
                .disabled(!hasDoc || tab?.viewMode == .grid)
                .help("Zoom")
            }

            // ── Right group 3 (rightmost): Reading mode ───────────────
            // Using Label (not bare Image) so NSToolbar can title the overflow
            // submenu "Reading Mode" instead of flattening the items.
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
                    Label("Reading Mode",
                          systemImage: tab?.readingMode.symbolName ?? ReadingMode.default.symbolName)
                        .symbolRenderingMode(.multicolor)
                        .labelStyle(.iconOnly)
                }
                .disabled(!hasDoc)
                .help("Reading Mode: \(tab?.readingMode.rawValue ?? "Default")")
            }

            // ── Rightmost: AI Assistant ────────────────────────────────
            ToolbarItem(placement: .primaryAction) {
                Button {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
                        appState.isAISidebarVisible.toggle()
                    }
                } label: {
                    Label("AI Assistant", systemImage: "sparkles")
                        .symbolVariant(appState.isAISidebarVisible ? .fill : .none)
                }
                .help(appState.isAISidebarVisible ? "Hide AI Assistant" : "Show AI Assistant")
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

// MARK: - Sidebar Resize Handle

/// A thin draggable divider that lets the user resize the sidebar.
/// Shows a resize cursor on hover, just like Finder / Xcode.
struct SidebarResizeHandle: View {

    @Binding var width: CGFloat
    /// When `true` dragging left increases width (right-sidebar handle).
    var flipped: Bool = false
    @State private var isHovered = false
    @State private var dragStartWidth: CGFloat = 0

    private let minWidth: CGFloat = 120
    // 2-column layout starts when availableWidth > 220 (sidebarWidth - 2*12 > 220 → sidebarWidth > 244)
    private let maxWidth: CGFloat = 244

    var body: some View {
        Rectangle()
            .fill(Color.primary.opacity(isHovered ? 0.18 : 0.08))
            .frame(width: 4)
            .onHover { hovered in
                isHovered = hovered
                if hovered {
                    NSCursor.resizeLeftRight.push()
                } else {
                    NSCursor.pop()
                }
            }
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { value in
                        if dragStartWidth == 0 { dragStartWidth = width }
                        let delta = flipped ? -value.translation.width : value.translation.width
                        width = min(maxWidth, max(minWidth, dragStartWidth + delta))
                    }
                    .onEnded { _ in dragStartWidth = 0 }
            )
    }
}
