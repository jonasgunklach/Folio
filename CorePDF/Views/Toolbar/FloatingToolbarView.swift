// FloatingToolbarView.swift
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

/// A pill-shaped, floating toolbar centered at the top of the content area.
/// Uses `.ultraThinMaterial` which renders as native Liquid Glass on macOS 26+.
struct FloatingToolbarView: View {

    @Environment(AppState.self) private var appState
    @Environment(PDFViewerViewModel.self) private var viewerViewModel: PDFViewerViewModel?

    var body: some View {
        HStack(spacing: 2) {
            // ── Left cluster: sidebar + navigation ──
            ToolbarButton(
                symbol: "sidebar.left",
                tooltip: "Toggle Sidebar",
                isActive: appState.isSidebarVisible
            ) {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                    appState.toggleSidebar()
                }
            }

            ToolbarDivider()

            ToolbarButton(symbol: "chevron.up", tooltip: "Previous Page") {
                navigatePage(forward: false)
            }
            .disabled(appState.activeTab == nil)

            if let tab = appState.activeTab {
                Text("\(tab.currentPageLabel) / \(tab.pageCount)")
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 64)
            }

            ToolbarButton(symbol: "chevron.down", tooltip: "Next Page") {
                navigatePage(forward: true)
            }
            .disabled(appState.activeTab == nil)

            ToolbarDivider()

            // ── Center cluster: tools ──
            ForEach(ActiveTool.allCases.filter(\.isPrimaryTool)) { tool in
                ToolbarButton(
                    symbol: tool.symbolName,
                    tooltip: tool.rawValue,
                    isActive: appState.activeTool == tool
                ) {
                    appState.activeTool = tool
                }
            }

            ToolbarDivider()

            // ── Right cluster: zoom + reading mode ──
            ToolbarButton(symbol: "minus.magnifyingglass", tooltip: "Zoom Out") {
                viewerViewModel?.zoomOut()
            }
            .disabled(viewerViewModel == nil)

            ToolbarButton(symbol: "1.magnifyingglass", tooltip: "Fit to Window") {
                viewerViewModel?.zoomToFit()
            }
            .disabled(viewerViewModel == nil)

            ToolbarButton(symbol: "plus.magnifyingglass", tooltip: "Zoom In") {
                viewerViewModel?.zoomIn()
            }
            .disabled(viewerViewModel == nil)

            ToolbarDivider()

            ReadingModeMenuButton()

            ToolbarButton(symbol: "bookmark", tooltip: "Bookmark Page") {
                bookmarkCurrentPage()
            }
            .disabled(appState.activeTab == nil)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
        .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
        .overlay {
            Capsule()
                .strokeBorder(.separator.opacity(0.4), lineWidth: 0.5)
        }
        .fixedSize()
    }

    // MARK: - Actions

    private func navigatePage(forward: Bool) {
        guard let tab = appState.activeTab else { return }
        let newIndex = forward
            ? min(tab.currentPageIndex + 1, tab.pageCount - 1)
            : max(tab.currentPageIndex - 1, 0)
        tab.currentPageIndex = newIndex
    }

    private func bookmarkCurrentPage() {
        guard let tab = appState.activeTab else { return }
        tab.toggleBookmark(at: tab.currentPageIndex)
    }
}

// MARK: - Reading Mode Menu

struct ReadingModeMenuButton: View {

    @Environment(AppState.self) private var appState

    var body: some View {
        Menu {
            ForEach(ReadingMode.allCases) { mode in
                Button {
                    appState.activeTab?.readingMode = mode
                } label: {
                    Label(mode.rawValue, systemImage: mode.symbolName)
                }
            }
        } label: {
            Image(systemName: appState.activeTab?.readingMode.symbolName ?? "sun.max")
                .symbolRenderingMode(.multicolor)
                .font(.system(size: 14))
                .frame(width: 28, height: 28)
        }
        .menuStyle(.borderlessButton)
        .help("Reading Mode")
        .disabled(appState.activeTab == nil)
    }
}

// MARK: - Reusable Components

struct ToolbarButton: View {

    let symbol: String
    let tooltip: String
    var isActive: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .symbolRenderingMode(.multicolor)
                .font(.system(size: 14))
                .frame(width: 28, height: 28)
                .background {
                    if isActive {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.accentColor.opacity(0.15))
                    }
                }
        }
        .buttonStyle(.plain)
        .foregroundStyle(isActive ? Color.accentColor : .primary)
        .help(tooltip)
    }
}

struct ToolbarDivider: View {
    var body: some View {
        Divider()
            .frame(height: 18)
            .padding(.horizontal, 4)
    }
}
