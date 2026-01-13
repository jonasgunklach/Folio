// PageOrganizerView.swift
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
import UniformTypeIdentifiers

// MARK: - Drag payload (Transferable)

/// Encodes an ordered list of page indices as JSON for intra-app drag/drop.
/// Using `.json` avoids any custom UTType declaration in Info.plist.
struct PageDragPayload: Transferable, Codable {
    var indices: [Int]
    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .json)
    }
}

/// Full-screen page organiser: thumbnail grid with drag-to-reorder, rotation,
/// multi-selection, delete and clipboard copy.
struct PageOrganizerView: View {

    var tab: DocumentTab
    @State private var viewModel = PageOrganizerViewModel()
    /// Index of the cell currently under an active drag, for visual feedback.
    @State private var dropTargetIndex: Int? = nil

    private let columns = [GridItem(.adaptive(minimum: 120, maximum: 160), spacing: 16)]

    var body: some View {
        VStack(spacing: 0) {

            // ── Toolbar ────────────────────────────────────────────────
            HStack(spacing: 6) {
                Text("\(viewModel.pages.count) Pages")
                    .font(.headline)

                if !viewModel.selectedIndices.isEmpty {
                    Text("· \(viewModel.selectedIndices.count) selected")
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Group {
                    Button {
                        viewModel.rotatePages(viewModel.selectedIndices, by: -90, in: tab.document)
                        tab.isModified = true
                    } label: { Image(systemName: "rotate.left") }
                    .help("Rotate Left")

                    Button {
                        viewModel.rotatePages(viewModel.selectedIndices, by: 90, in: tab.document)
                        tab.isModified = true
                    } label: { Image(systemName: "rotate.right") }
                    .help("Rotate Right")
                }
                .disabled(viewModel.selectedIndices.isEmpty)

                Divider().frame(height: 16)

                Button {
                    viewModel.copySelectedPages()
                } label: { Image(systemName: "doc.on.doc") }
                .disabled(viewModel.selectedIndices.isEmpty)
                .help("Copy Selected Pages (⌘C)")

                Button {
                    if viewModel.pastePages(into: tab.document) {
                        tab.isModified = true
                    }
                } label: { Image(systemName: "doc.on.clipboard") }
                .help("Paste Pages from Clipboard (⌘V)")

                Button {
                    viewModel.addEmptyPage(into: tab.document)
                    tab.isModified = true
                } label: { Image(systemName: "plus.rectangle") }
                .help("Add Empty Page")

                Divider().frame(height: 16)

                Button(role: .destructive) {
                    viewModel.deletePages(viewModel.selectedIndices, in: tab.document)
                    tab.isModified = true
                    tab.currentPageIndex = min(tab.currentPageIndex,
                                              max(0, viewModel.pages.count - 1))
                } label: { Image(systemName: "trash") }
                .disabled(viewModel.selectedIndices.isEmpty)
                .help("Delete Selected Pages")

                Divider().frame(height: 16)

                Button("Select All") {
                    viewModel.selectedIndices = Set(viewModel.pages.indices)
                }
                .disabled(viewModel.pages.isEmpty)

                Button("Deselect") {
                    viewModel.selectedIndices = []
                }
                .disabled(viewModel.selectedIndices.isEmpty)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Divider()

            // ── Page Grid ──────────────────────────────────────────────
            ScrollView {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(Array(viewModel.pages.enumerated()), id: \.offset) { index, page in
                        PageThumbnailCell(
                            page: page,
                            pageIndex: index,
                            isSelected: viewModel.selectedIndices.contains(index),
                            isDropTarget: dropTargetIndex == index,
                            refreshToken: viewModel.refreshToken
                        )
                        // ── Selection ──────────────────────────────────
                        .onTapGesture {
                            if NSEvent.modifierFlags.contains(.command) {
                                if viewModel.selectedIndices.contains(index) {
                                    viewModel.selectedIndices.remove(index)
                                } else {
                                    viewModel.selectedIndices.insert(index)
                                }
                            } else if NSEvent.modifierFlags.contains(.shift),
                                      let anchor = viewModel.selectedIndices.min() {
                                let lo = min(anchor, index), hi = max(anchor, index)
                                viewModel.selectedIndices = Set(lo...hi)
                            } else {
                                viewModel.selectedIndices = viewModel.selectedIndices == [index] ? [] : [index]
                            }
                        }
                        // ── Context Menu ───────────────────────────────
                        .contextMenu { contextMenu(for: index) }
                        // ── Drag ───────────────────────────────────────
                        .draggable(
                            PageDragPayload(indices: {
                                if !viewModel.selectedIndices.contains(index) {
                                    viewModel.selectedIndices = [index]
                                }
                                return Array(viewModel.selectedIndices).sorted()
                            }())
                        )
                        // ── Drop onto this cell (insert before) ────────
                        .dropDestination(for: PageDragPayload.self) { items, _ in
                            guard let payload = items.first else { return false }
                            viewModel.movePages(payload.indices, before: index, in: tab.document)
                            tab.isModified = true
                            return true
                        } isTargeted: { targeted in
                            dropTargetIndex = targeted ? index : nil
                        }
                    }
                }
                .padding(20)
                // ── Drop after last page (append) ──────────────────
                .dropDestination(for: PageDragPayload.self) { items, _ in
                    guard let payload = items.first else { return false }
                    viewModel.movePages(payload.indices,
                                        before: viewModel.pages.count,
                                        in: tab.document)
                    tab.isModified = true
                    dropTargetIndex = nil
                    return true
                }
            }
            .background(Color(NSColor.textBackgroundColor))
        }
        .onAppear {
            viewModel.load(document: tab.document)
        }
        // ── Keyboard shortcuts ─────────────────────────────────────
        .background {
            Group {
                Button("") {
                    viewModel.copySelectedPages()
                }.keyboardShortcut("c", modifiers: .command)
                Button("") {
                    if viewModel.pastePages(into: tab.document) { tab.isModified = true }
                }.keyboardShortcut("v", modifiers: .command)
            }
            .opacity(0).frame(width: 0, height: 0).allowsHitTesting(false)
        }
    }

    // MARK: - Context Menu

    @ViewBuilder
    private func contextMenu(for index: Int) -> some View {
        Button {
            viewModel.rotatePages(Set([index]), by: -90, in: tab.document)
            tab.isModified = true
        } label: { Label("Rotate Left", systemImage: "rotate.left") }

        Button {
            viewModel.rotatePages(Set([index]), by: 90, in: tab.document)
            tab.isModified = true
        } label: { Label("Rotate Right", systemImage: "rotate.right") }

        Divider()

        Button {
            // Copy just this one page (select it first so copySelectedPages works).
            let prev = viewModel.selectedIndices
            viewModel.selectedIndices = [index]
            viewModel.copySelectedPages()
            viewModel.selectedIndices = prev
        } label: { Label("Copy Page", systemImage: "doc.on.doc") }

        Button {
            _ = viewModel.extractPages(Set([index]))
        } label: { Label("Extract Page…", systemImage: "arrow.up.doc") }

        Divider()

        Button(role: .destructive) {
            viewModel.deletePages(Set([index]), in: tab.document)
            tab.isModified = true
            tab.currentPageIndex = min(tab.currentPageIndex,
                                       max(0, viewModel.pages.count - 1))
        } label: { Label("Delete Page", systemImage: "trash") }
    }
}

// MARK: - Cell

struct PageThumbnailCell: View {

    let page: PDFPage
    let pageIndex: Int
    let isSelected: Bool
    let isDropTarget: Bool
    let refreshToken: Int

    @State private var thumbnail: NSImage?

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(.tertiary)

                if let thumbnail {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                } else {
                    ProgressView()
                }
            }
            .aspectRatio(0.77, contentMode: .fit)
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(Color.accentColor, lineWidth: 3)
                } else if isDropTarget {
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(Color.accentColor.opacity(0.55), lineWidth: 2)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.accentColor.opacity(0.08))
                        )
                }
            }
            .shadow(color: .black.opacity(isSelected ? 0.20 : 0.07), radius: 4, y: 2)

            Text("Page \(pageIndex + 1)")
                .font(.caption2)
                .foregroundStyle(isSelected ? Color.accentColor : .secondary)
        }
        // Re-generate thumbnail whenever refreshToken changes (rotation, delete, reorder).
        .task(id: refreshToken) {
            nonisolated(unsafe) let p = page
            thumbnail = await Task.detached(priority: .background) {
                p.thumbnail(of: CGSize(width: 200, height: 260), for: .mediaBox)
            }.value
        }
    }
}

