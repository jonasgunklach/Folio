// PageOrganizerViewModel.swift
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

import Foundation
import SwiftUI
import PDFKit
import AppKit

/// Manages page-level operations: reorder, rotate, delete, extract, copy.
///
/// `pages` is the single source of truth for page order.
/// Every mutating operation rebuilds the PDFDocument in-place and bumps
/// `refreshToken` so thumbnail cells re-render.
@MainActor
@Observable
final class PageOrganizerViewModel {

    /// Live ordered page objects — always in sync with the document.
    var pages: [PDFPage] = []

    /// Grid positions (into `pages`) that are currently highlighted.
    var selectedIndices: Set<Int> = []

    /// Increments after every content change; thumbnail tasks key on this.
    var refreshToken: Int = 0

    // MARK: - Load

    func load(document: PDFDocument) {
        pages = (0 ..< document.pageCount).compactMap { document.page(at: $0) }
        selectedIndices = []
    }

    // MARK: - Move (Drag & Drop)

    /// Inserts `draggedIndices` before `targetIndex`.
    /// Handles multi-page drags: indices before the target shift the insertion point.
    func movePages(_ draggedIndices: [Int], before targetIndex: Int, in document: PDFDocument) {
        let sorted = draggedIndices.sorted()
        guard !sorted.isEmpty else { return }
        // Count dragged pages that sit before the target — target index shifts left by this.
        let countBefore = sorted.filter { $0 < targetIndex }.count
        let adjustedTarget = max(0, targetIndex - countBefore)

        let pagesToMove = sorted.map { pages[$0] }
        for i in sorted.reversed() { pages.remove(at: i) }
        let insertAt = min(adjustedTarget, pages.count)
        pages.insert(contentsOf: pagesToMove, at: insertAt)
        // Re-select moved pages at their new positions.
        selectedIndices = Set(insertAt ..< (insertAt + pagesToMove.count))
        applyOrder(to: document)
    }

    // MARK: - Rotation

    func rotatePages(_ indices: Set<Int>, by degrees: Int, in document: PDFDocument) {
        for i in indices where i < pages.count {
            let current = pages[i].rotation
            pages[i].rotation = ((current + degrees) % 360 + 360) % 360
        }
        refreshToken += 1   // document already mutated in-place; just refresh thumbnails
    }

    // MARK: - Deletion

    func deletePages(_ indices: Set<Int>, in document: PDFDocument) {
        for i in indices.sorted(by: >) where i < pages.count {
            pages.remove(at: i)
        }
        selectedIndices = []
        applyOrder(to: document)
    }

    // MARK: - Copy to Clipboard

    func copySelectedPages() {
        let sorted = selectedIndices.sorted()
        guard !sorted.isEmpty else { return }
        let doc = PDFDocument()
        sorted.enumerated().forEach { at, src in
            guard src < pages.count, let copy = pages[src].copy() as? PDFPage else { return }
            doc.insert(copy, at: at)
        }
        guard let data = doc.dataRepresentation() else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setData(data, forType: .pdf)
    }

    // MARK: - Extract

    func extractPages(_ indices: Set<Int>) -> PDFDocument? {
        let doc = PDFDocument()
        indices.sorted().enumerated().forEach { at, src in
            guard src < pages.count, let copy = pages[src].copy() as? PDFPage else { return }
            doc.insert(copy, at: at)
        }
        return doc.pageCount > 0 ? doc : nil
    }

    // MARK: - Merge

    func mergeDocument(_ other: PDFDocument, into base: PDFDocument) {
        let insertFrom = base.pageCount
        (0 ..< other.pageCount).forEach { i in
            guard let page = other.page(at: i) else { return }
            base.insert(page, at: insertFrom + i)
        }
        load(document: base)
    }

    // MARK: - Private

    private func applyOrder(to document: PDFDocument) {
        for i in stride(from: document.pageCount - 1, through: 0, by: -1) {
            document.removePage(at: i)
        }
        for (i, page) in pages.enumerated() {
            document.insert(page, at: i)
        }
        refreshToken += 1
    }
}

