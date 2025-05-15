// PDFTabContainer.swift
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

// MARK: - Tab Bar

/// Safari-style tab strip for the toolbar `.principal` placement.
/// Tabs are transparent-backed pills; the toolbar chrome (Liquid Glass on
/// macOS 26) provides the overall background — no double-material stacking.
struct DocumentTabBar: View {

    @Environment(AppState.self) private var appState

    var body: some View {
        HStack(spacing: 0) {
            // Scrollable tab pills
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 1) {
                    ForEach(appState.tabs) { tab in
                        DocumentTabItem(tab: tab)
                            .transition(
                                .asymmetric(
                                    insertion: .scale(scale: 0.88, anchor: .leading)
                                        .combined(with: .opacity),
                                    removal: .scale(scale: 0.88, anchor: .leading)
                                        .combined(with: .opacity)
                                )
                            )
                    }
                }
                .padding(.horizontal, 4)
                .animation(.spring(response: 0.28, dampingFraction: 0.78), value: appState.tabs.map(\.id))
            }

            // "+" open-new-tab button
            Button {
                appState.isFileImporterPresented = true
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Open PDF (⌘O)")
            .padding(.trailing, 4)
        }
        // Transparent background — toolbar provides the glass chrome
    }
}

// MARK: - Tab Item

struct DocumentTabItem: View {

    @Environment(AppState.self) private var appState
    let tab: DocumentTab
    @State private var isHovered = false

    private var isActive: Bool { appState.activeTabID == tab.id }

    var body: some View {
        HStack(spacing: 6) {
            // Document type icon — replaced by a spinner while saving
            if tab.isSaving {
                ProgressView()
                    .progressViewStyle(.circular)
                    .scaleEffect(0.5)
                    .frame(width: 14, height: 14)
            } else {
                Image(systemName: tab.isModified ? "doc.badge.ellipsis" : "doc.fill")
                    .symbolRenderingMode(.multicolor)
                    .font(.system(size: 10))
                    .foregroundStyle(isActive ? Color.accentColor : Color.secondary)
            }

            // File name
            Text(tab.title)
                .font(.system(size: 12))
                .lineLimit(1)
                .foregroundStyle(isActive ? Color.primary : Color.secondary)
                .frame(maxWidth: 140, alignment: .leading)

            // Close button — visible on hover or when active
            Button {
                withAnimation(.spring(response: 0.22, dampingFraction: 0.75)) {
                    appState.closeTab(tab.id)
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 15, height: 15)
                    .background(
                        Circle()
                            .fill(Color.primary.opacity(isHovered ? 0.12 : 0))
                    )
            }
            .buttonStyle(.plain)
            .opacity((isActive || isHovered) ? 1 : 0)
        }
        .padding(.horizontal, 10)
        .frame(minWidth: 90, maxWidth: 170)
        .frame(height: 26)
        // ── Background ──────────────────────────────────────────────
        .background {
            RoundedRectangle(cornerRadius: 7)
                .fill(
                    isActive
                        ? Color(NSColor.controlBackgroundColor)
                        : Color.primary.opacity(isHovered ? 0.06 : 0)
                )
                // Elevated shadow only on active tab, like Safari
                .shadow(
                    color: isActive ? .black.opacity(0.10) : .clear,
                    radius: 3, y: 1
                )
        }
        .contentShape(RoundedRectangle(cornerRadius: 7))
        .onTapGesture {
            appState.activateTab(tab.id)
        }
        .onHover { hovered in
            withAnimation(.easeInOut(duration: 0.12)) { isHovered = hovered }
        }
        .animation(.spring(response: 0.22, dampingFraction: 0.8), value: isActive)
    }
}

