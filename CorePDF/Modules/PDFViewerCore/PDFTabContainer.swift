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
import PDFKit

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

            // "+" new tab menu
            Menu {
                Button("Open PDF…") { appState.isFileImporterPresented = true }
                Button("New Empty Document") { appState.openEmptyDocument() }
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .help("New Tab")
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
    @State private var coverImage: NSImage?

    private var isActive: Bool { appState.activeTabID == tab.id }

    var body: some View {
        HStack(spacing: 5) {
            // First-page mini-thumbnail (or spinner while saving)
            ZStack(alignment: .bottomTrailing) {
                if tab.isSaving {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .scaleEffect(0.5)
                        .frame(width: 18, height: 22)
                } else if let img = coverImage {
                    Image(nsImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 18, height: 22)
                        .clipShape(RoundedRectangle(cornerRadius: 2))
                        // Visible border so white pages don't vanish against the toolbar
                        .overlay(
                            RoundedRectangle(cornerRadius: 2)
                                .strokeBorder(Color.primary.opacity(0.18), lineWidth: 0.75)
                        )
                        .shadow(color: .black.opacity(0.12), radius: 1, y: 0.5)
                        .opacity(isActive ? 1 : 0.65)
                } else {
                    Image(systemName: "doc.fill")
                        .symbolRenderingMode(.multicolor)
                        .font(.system(size: 10))
                        .frame(width: 18, height: 22)
                        .foregroundStyle(isActive ? Color.accentColor : Color.secondary)
                }

                // Unsaved changes indicator — blue dot bottom-right corner
                if tab.isModified {
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 6, height: 6)
                        .offset(x: 3, y: 3)
                }
            }

            // Close button — visible on hover or when active
            Button {
                withAnimation(.spring(response: 0.22, dampingFraction: 0.75)) {
                    appState.closeTab(tab.id)
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 14, height: 14)
                    .background(
                        Circle()
                            .fill(Color.primary.opacity(isHovered ? 0.12 : 0))
                    )
            }
            .buttonStyle(.plain)
            .opacity((isActive || isHovered) ? 1 : 0)
        }
        .padding(.horizontal, 8)
        .frame(width: 52, height: 30)
        // ── Background ──────────────────────────────────────────────
        .background {
            RoundedRectangle(cornerRadius: 7)
                .fill(
                    isActive
                        ? Color(NSColor.controlBackgroundColor)
                        : Color.primary.opacity(isHovered ? 0.06 : 0)
                )
                .shadow(
                    color: isActive ? .black.opacity(0.10) : .clear,
                    radius: 3, y: 1
                )
        }
        .contentShape(RoundedRectangle(cornerRadius: 7))
        .help(tab.isModified ? "\(tab.title) — Unsaved changes" : tab.title)
        .onTapGesture {
            appState.activateTab(tab.id)
        }
        .onHover { hovered in
            withAnimation(.easeInOut(duration: 0.12)) { isHovered = hovered }
        }
        .animation(.spring(response: 0.22, dampingFraction: 0.8), value: isActive)
        .task(id: tab.id) {
            coverImage = await Task.detached(priority: .utility) {
                tab.document.page(at: 0)?.thumbnail(of: CGSize(width: 36, height: 44), for: .mediaBox)
            }.value
        }
    }
}

// MARK: - Tab Bar Row (full-width, below toolbar)

/// Safari-style tab bar: equal-width tabs on a gray strip,
/// active tab is a white rounded pill with shadow, inactive tabs are transparent.
struct TabBarRowView: View {

    @Environment(AppState.self) private var appState

    var body: some View {
        HStack(spacing: 4) {
            ForEach(appState.tabs) { tab in
                NativeTabCell(tab: tab)
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }

            // "+" new tab menu
            Menu {
                Button("Open PDF…") { appState.isFileImporterPresented = true }
                Button("New Empty Document") { appState.openEmptyDocument() }
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .help("New Tab")
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .frame(height: 38)
        .background(.bar)
        .animation(.spring(response: 0.28, dampingFraction: 0.78), value: appState.tabs.map(\.id))
    }
}

// MARK: - Native Tab Cell

private struct NativeTabCell: View {

    @Environment(AppState.self) private var appState
    let tab: DocumentTab
    @State private var isHovered = false

    private var isActive: Bool { appState.activeTabID == tab.id }

    var body: some View {
        HStack(spacing: 5) {
            if tab.isSaving {
                ProgressView()
                    .progressViewStyle(.circular)
                    .scaleEffect(0.5)
                    .frame(width: 12, height: 12)
            } else {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: "doc.fill")
                        .symbolRenderingMode(.multicolor)
                        .font(.system(size: 10))
                        .foregroundStyle(isActive ? Color.accentColor : Color.secondary)
                    if tab.isModified {
                        Circle()
                            .fill(Color.accentColor)
                            .frame(width: 5, height: 5)
                            .offset(x: 4, y: -3)
                    }
                }
            }

            Text(tab.title)
                .font(.system(size: 12))
                .lineLimit(1)
                .foregroundStyle(isActive ? Color.primary : Color.secondary)

            Button {
                withAnimation(.spring(response: 0.22, dampingFraction: 0.75)) {
                    appState.closeTab(tab.id)
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 14, height: 14)
                    .background(Circle().fill(Color.primary.opacity(isHovered ? 0.12 : 0)))
            }
            .buttonStyle(.plain)
            .opacity((isActive || isHovered) ? 1 : 0)
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity)
        .frame(height: 30)
        .background {
            if isActive {
                Capsule()
                    .fill(.regularMaterial)
                    .shadow(color: .black.opacity(0.10), radius: 2, y: 1)
                    .overlay(Capsule().strokeBorder(.separator.opacity(0.4), lineWidth: 0.5))
            } else if isHovered {
                Capsule()
                    .fill(Color.primary.opacity(0.06))
            }
        }
        .contentShape(Capsule())
        .onTapGesture { appState.activateTab(tab.id) }
        .onHover { isHovered = $0 }
        .animation(.easeInOut(duration: 0.1), value: isActive)
    }
}

