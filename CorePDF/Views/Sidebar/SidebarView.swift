// SidebarView.swift
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

// MARK: - Sidebar Section Enum

enum SidebarSection: String, CaseIterable, Identifiable {
    case thumbnails  = "Thumbnails"
    case outline     = "Outline"
    case bookmarks   = "Bookmarks"
    case annotations = "Annotations"

    var id: String { rawValue }

    var symbolName: String {
        switch self {
        case .thumbnails:   "rectangle.grid.2x2"
        case .outline:      "list.bullet.indent"
        case .bookmarks:    "bookmark.fill"
        case .annotations:  "pencil.and.outline"
        }
    }
}

// MARK: - Sidebar Root

struct SidebarView: View {

    @Environment(AppState.self) private var appState
    @State private var selectedSection: SidebarSection = .thumbnails

    var body: some View {
        VStack(spacing: 0) {
            // Reserve space matching the floating toolbar height
            Color.clear.frame(height: 56)

            SidebarSectionPicker(selected: $selectedSection)
                .padding(.horizontal, 8)
                .padding(.bottom, 8)

            Divider()

            Group {
                if let tab = appState.activeTab {
                    switch selectedSection {
                    case .thumbnails:
                        ThumbnailListView(
                            document: tab.document,
                            activeTab: tab,
                            isInteractive: tab.viewMode == .scroll
                        )
                    case .outline:
                        OutlineView(document: tab.document)
                    case .bookmarks:
                        BookmarksView(activeTab: tab)
                    case .annotations:
                        AnnotationsListView(document: tab.document)
                    }
                } else {
                    ContentUnavailableView(
                        "No Document",
                        systemImage: "doc",
                        description: Text("Open a PDF to see its contents here.")
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color(NSColor.windowBackgroundColor))
    }
}

// MARK: - Section Picker

struct SidebarSectionPicker: View {

    @Binding var selected: SidebarSection

    var body: some View {
        HStack(spacing: 0) {
            ForEach(SidebarSection.allCases) { section in
                Button {
                    selected = section
                } label: {
                    Image(systemName: section.symbolName)
                        .symbolRenderingMode(.multicolor)
                        .font(.system(size: 13))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 5)
                        .background {
                            if selected == section {
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(.background.opacity(0.85))
                            }
                        }
                }
                .buttonStyle(.plain)
                .foregroundStyle(selected == section ? .primary : .secondary)
            }
        }
        .padding(3)
        .background(RoundedRectangle(cornerRadius: 8).fill(.quaternary))
    }
}

// MARK: - Thumbnails

struct ThumbnailListView: View {

    let document: PDFDocument
    let activeTab: DocumentTab
    /// When false, thumbnails show but tapping them does nothing (e.g. in grid view).
    var isInteractive: Bool = true

    /// Snapshot of pages re-computed when the document changes.
    private var pages: [(index: Int, page: PDFPage)] {
        (0..<document.pageCount).compactMap { i in
            guard let p = document.page(at: i) else { return nil }
            return (i, p)
        }
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 6) {
                ForEach(pages, id: \.page.hashValue) { entry in
                    ThumbnailRowView(
                        page: entry.page,
                        pageIndex: entry.index,
                        isActive: activeTab.currentPageIndex == entry.index
                    ) {
                        guard isInteractive else { return }
                        activeTab.currentPageIndex = entry.index
                    }
                    .opacity(isInteractive ? 1 : 0.45)
                    .allowsHitTesting(isInteractive)
                }
            }
            .padding(8)
        }
        // Force re-evaluation when pages are added/removed/reordered
        .id(document.pageCount)
    }
}

struct ThumbnailRowView: View {

    let page: PDFPage
    let pageIndex: Int
    let isActive: Bool
    let onTap: () -> Void
    @State private var thumbnail: NSImage?

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 3)
                    .fill(.tertiary)

                if let thumbnail {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                } else {
                    ProgressView().scaleEffect(0.5)
                }
            }
            .frame(width: 54, height: 70)
            .overlay {
                if isActive {
                    RoundedRectangle(cornerRadius: 3)
                        .strokeBorder(Color.accentColor, lineWidth: 2)
                }
            }
            .shadow(color: .black.opacity(isActive ? 0.18 : 0.06), radius: 3, y: 1)

            VStack(alignment: .leading, spacing: 2) {
                Text("Page \(pageIndex + 1)")
                    .font(.caption)
                    .foregroundStyle(isActive ? .primary : .secondary)
            }

            Spacer()
        }
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
        .background(isActive ? Color.accentColor.opacity(0.08) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        // Re-generate thumbnail whenever the actual page object changes.
        .task(id: ObjectIdentifier(page)) {
            thumbnail = await Task.detached(priority: .background) {
                page.thumbnail(of: CGSize(width: 108, height: 140), for: .mediaBox)
            }.value
        }
    }
}

// MARK: - Outline

struct OutlineView: View {

    let document: PDFDocument

    var body: some View {
        if let root = document.outlineRoot, root.numberOfChildren > 0 {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    ForEach(0..<root.numberOfChildren, id: \.self) { i in
                        if let child = root.child(at: i) {
                            OutlineItemView(item: child, depth: 0)
                        }
                    }
                }
                .padding(8)
            }
        } else {
            ContentUnavailableView(
                "No Outline",
                systemImage: "list.bullet.indent",
                description: Text("This document has no table of contents.")
            )
        }
    }
}

struct OutlineItemView: View {

    let item: PDFOutline
    let depth: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(item.label ?? "Untitled")
                .font(.caption)
                .foregroundStyle(.primary)
                .padding(.leading, CGFloat(depth) * 12 + 8)
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity, alignment: .leading)

            ForEach(0..<item.numberOfChildren, id: \.self) { i in
                if let child = item.child(at: i) {
                    OutlineItemView(item: child, depth: depth + 1)
                }
            }
        }
    }
}

// MARK: - Bookmarks

struct BookmarksView: View {

    let activeTab: DocumentTab

    var body: some View {
        if activeTab.bookmarkedPageIndices.isEmpty {
            ContentUnavailableView(
                "No Bookmarks",
                systemImage: "bookmark",
                description: Text("Bookmark pages using the toolbar button.")
            )
        } else {
            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(activeTab.bookmarkedPageIndices.sorted(), id: \.self) { index in
                        HStack(spacing: 8) {
                            Image(systemName: "bookmark.fill")
                                .foregroundStyle(Color.accentColor)
                                .font(.caption)
                            Text("Page \(index + 1)")
                                .font(.caption)
                            Spacer()
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                    }
                }
                .padding(.vertical, 8)
            }
        }
    }
}

// MARK: - Annotations List

struct AnnotationsListView: View {

    let document: PDFDocument

    private var items: [(pageIndex: Int, annotation: PDFAnnotation)] {
        (0..<document.pageCount).flatMap { idx -> [(pageIndex: Int, annotation: PDFAnnotation)] in
            guard let page = document.page(at: idx) else { return [] }
            return page.annotations.map { (pageIndex: idx, annotation: $0) }
        }
    }

    var body: some View {
        if items.isEmpty {
            ContentUnavailableView(
                "No Annotations",
                systemImage: "pencil.and.outline",
                description: Text("Add annotations to see them listed here.")
            )
        } else {
            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                        AnnotationRowView(pageIndex: item.pageIndex, annotation: item.annotation)
                    }
                }
                .padding(8)
            }
        }
    }
}

struct AnnotationRowView: View {

    let pageIndex: Int
    let annotation: PDFAnnotation

    private var symbolName: String {
        switch annotation.type {
        case "Highlight":   "highlighter"
        case "StrikeOut":   "strikethrough"
        case "Underline":   "underline"
        case "Ink":         "pencil.tip"
        case "Text":        "bubble.left.fill"
        default:            "pencil.and.outline"
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbolName)
                .symbolRenderingMode(.multicolor)
                .font(.caption)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(annotation.type ?? "Annotation")
                    .font(.caption.bold())

                if let contents = annotation.contents, !contents.isEmpty {
                    Text(contents)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Text("Page \(pageIndex + 1)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 6).fill(.quaternary))
    }
}

// MARK: - Thumbnail Sidebar

/// Narrow thumbnail-only sidebar shown when the sidebar toggle is on.
/// Uses the same `ThumbnailListView` as the full `SidebarView`.
struct ThumbnailSidebarView: View {

    let document: PDFDocument
    let activeTab: DocumentTab
    var isInteractive: Bool = true

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(isInteractive ? "Pages" : "Pages (Grid View)")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(document.pageCount) pages")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)

            Divider()

            ThumbnailListView(document: document, activeTab: activeTab,
                              isInteractive: isInteractive)
        }
        .background(Color(NSColor.windowBackgroundColor))
        // Force header page count + list to re-evaluate when document is modified
        .id(activeTab.isModified)
    }
}

