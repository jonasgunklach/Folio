// MainToolbarView.swift
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

/// Integrated single-row toolbar shown below the tab bar.
/// Layout (left → right):
///   [Open] | [‹ pg/total ›] | [− zoom% +] | [cursor] | [H U S] | [pen text] | [stamp sig mic] ··· [mode]
struct MainToolbarView: View {

    @Environment(AppState.self) private var appState

    private var tab: DocumentTab? { appState.activeTab }
    private var vm: PDFViewerViewModel? { tab?.viewerViewModel }
    private var hasDoc: Bool { tab != nil }

    var body: some View {
        HStack(spacing: 0) {

            // ── Open ──────────────────────────────────────────────────
            ToolbarIconButton(symbol: "folder.badge.plus", help: "Open PDF (⌘O)") {
                appState.isFileImporterPresented = true
            }
            .padding(.leading, 8)

            tbSep

            // ── Page navigation ───────────────────────────────────────
            HStack(spacing: 2) {
                ToolbarIconButton(symbol: "chevron.left", help: "Previous Page", enabled: hasDoc) {
                    navigatePage(forward: false)
                }

                Group {
                    if let tab {
                        Text("\(tab.currentPageLabel) / \(tab.pageCount)")
                    } else {
                        Text("— / —")
                            .foregroundStyle(.tertiary)
                    }
                }
                .font(.system(size: 11, weight: .medium).monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(minWidth: 64, alignment: .center)

                ToolbarIconButton(symbol: "chevron.right", help: "Next Page", enabled: hasDoc) {
                    navigatePage(forward: true)
                }
            }

            tbSep

            // ── Zoom ──────────────────────────────────────────────────
            HStack(spacing: 2) {
                ToolbarIconButton(symbol: "minus", help: "Zoom Out", enabled: hasDoc) {
                    vm?.zoomOut()
                }

                Button {
                    vm?.zoomToFit()
                } label: {
                    Text(vm.map { String(format: "%.0f%%", $0.scaleFactor * 100) } ?? "—%")
                        .font(.system(size: 11, weight: .medium).monospacedDigit())
                        .frame(minWidth: 44)
                }
                .buttonStyle(ToolbarItemButtonStyle())
                .disabled(!hasDoc)
                .help("Reset Zoom")

                ToolbarIconButton(symbol: "plus", help: "Zoom In", enabled: hasDoc) {
                    vm?.zoomIn()
                }
            }

            tbSep

            // ── Cursor ────────────────────────────────────────────────
            toolBtn(.select)

            tbSep

            // ── Text markup ───────────────────────────────────────────
            HStack(spacing: 2) {
                toolBtn(.highlight)
                toolBtn(.underline)
                toolBtn(.strikethrough)
            }

            tbSep

            // ── Drawing ───────────────────────────────────────────────
            HStack(spacing: 2) {
                toolBtn(.freehand)
                toolBtn(.text)
            }

            tbSep

            // ── Insert ────────────────────────────────────────────────
            HStack(spacing: 2) {
                toolBtn(.stamp)
                toolBtn(.signature)
                toolBtn(.audioNote)
            }

            Spacer()

            // ── Reading mode ─────────────────────────────────────────
            readingModeMenu
                .padding(.trailing, 8)
        }
        .frame(height: 46)
        .background(.bar)
    }

    // MARK: - Sub-views

    private var readingModeMenu: some View {
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
                .font(.system(size: 14))
                .frame(width: 28, height: 28)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .disabled(!hasDoc)
        .help("Reading Mode")
    }

    @ViewBuilder
    private func toolBtn(_ tool: ActiveTool) -> some View {
        let isActive = appState.activeTool == tool
        Button {
            if hasDoc { appState.activeTool = tool }
        } label: {
            Image(systemName: tool.symbolName)
                .symbolRenderingMode(.multicolor)
                .font(.system(size: 14))
                .frame(width: 28, height: 28)
        }
        .buttonStyle(ToolbarItemButtonStyle(isActive: isActive))
        .disabled(!hasDoc)
        .help(tool.rawValue)
    }

    private var tbSep: some View {
        Divider()
            .frame(height: 20)
            .padding(.horizontal, 8)
    }

    // MARK: - Actions

    private func navigatePage(forward: Bool) {
        guard let tab else { return }
        let newIndex = forward
            ? min(tab.currentPageIndex + 1, tab.pageCount - 1)
            : max(tab.currentPageIndex - 1, 0)
        tab.currentPageIndex = newIndex
    }
}

// MARK: - Reusable button components

/// Consistent style for all toolbar buttons.
struct ToolbarItemButtonStyle: ButtonStyle {
    var isActive: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14))
            .foregroundStyle(isActive ? Color.accentColor : Color.primary)
            .background {
                RoundedRectangle(cornerRadius: 6)
                    .fill(
                        isActive
                            ? Color.accentColor.opacity(0.15)
                            : configuration.isPressed
                                ? Color.primary.opacity(0.08)
                                : Color.clear
                    )
            }
    }
}

/// Icon-only toolbar button built on `ToolbarItemButtonStyle`.
struct ToolbarIconButton: View {
    let symbol: String
    let help: String
    var enabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14))
                .frame(width: 28, height: 28)
        }
        .buttonStyle(ToolbarItemButtonStyle())
        .disabled(!enabled)
        .help(help)
    }
}
