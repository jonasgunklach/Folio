// DocumentTab.swift
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

import AppKit
import Foundation
import PDFKit
import UniformTypeIdentifiers

/// Represents a single open PDF document in the tabbed interface.
/// Uses reference semantics so property mutations propagate automatically
/// through the Observation framework.
@MainActor
@Observable
final class DocumentTab: Identifiable {

    let id: UUID = UUID()
    let document: PDFDocument
    let url: URL?
    private let securityScopeActive: Bool

    var title: String
    var isModified: Bool = false
    /// `true` while a background save is in flight. Drives the toolbar progress indicator.
    var isSaving: Bool = false
    var readingMode: ReadingMode
    var viewMode: ViewMode
    var currentPageIndex: Int = 0
    var bookmarkedPageIndices: Set<Int> = []

    /// Owns per-document viewer state (zoom, display mode, TTS).
    let viewerViewModel: PDFViewerViewModel = PDFViewerViewModel()

    /// Owns annotation tool settings (colors, opacity).
    let annotationViewModel: AnnotationManagerViewModel = AnnotationManagerViewModel()

    init(document: PDFDocument, url: URL? = nil, securityScopeActive: Bool = false) {
        self.document = document
        self.url = url
        self.securityScopeActive = securityScopeActive
        self.title = url?.lastPathComponent ?? "Untitled"
        let s = SettingsStore.shared
        self.readingMode = s.defaultReadingMode
        self.viewMode    = s.defaultViewMode
    }

    /// Relinquishes any held security-scoped resource access. Called when the tab closes.
    func releaseSecurityScope() {
        if securityScopeActive, let url {
            url.stopAccessingSecurityScopedResource()
        }
    }

    // MARK: - Convenience

    var pageCount: Int { document.pageCount }

    var currentPageLabel: String {
        guard let page = document.page(at: currentPageIndex),
              let label = page.label,
              !label.isEmpty else {
            return "\(currentPageIndex + 1)"
        }
        return label
    }

    func toggleBookmark(at pageIndex: Int) {
        if bookmarkedPageIndices.contains(pageIndex) {
            bookmarkedPageIndices.remove(pageIndex)
        } else {
            bookmarkedPageIndices.insert(pageIndex)
        }
    }

    // MARK: - Persistence

    /// Saves to the original URL, or presents an NSSavePanel if unavailable.
    /// `dataRepresentation()` and the disk write both run on a background thread
    /// so the app stays responsive with large files.
    func save() async {
        guard !isSaving else { return }
        if let url {
            await performWrite(to: url, fallbackToPanel: true)
        } else {
            await saveWithPanel()
        }
    }

    /// Always presents an NSSavePanel (used for "Save As…").
    func saveWithPanel() async {
        guard !isSaving else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = url?.lastPathComponent
            ?? (title.hasSuffix(".pdf") ? title : title + ".pdf")
        if let dir = url?.deletingLastPathComponent() { panel.directoryURL = dir }
        guard panel.runModal() == .OK, let dest = panel.url else { return }
        await performWrite(to: dest, fallbackToPanel: false)
    }

    // Both PDF serialisation and disk write run on a background thread so the
    // main actor (and UI) are never blocked. PDFDocument.dataRepresentation()
    // is read-only and thread-safe; nonisolated(unsafe) is the Swift 6
    // escape hatch for Obj-C types that lack Sendable conformance.
    private func performWrite(to destination: URL, fallbackToPanel: Bool) async {
        isSaving = true
        defer { isSaving = false }
        nonisolated(unsafe) let doc = document
        let success = await Task.detached(priority: .userInitiated) {
            guard let data = doc.dataRepresentation() else { return false }
            do {
                try data.write(to: destination, options: .atomic)
                return true
            } catch {
                return false
            }
        }.value
        if success {
            isModified = false
        } else if fallbackToPanel {
            await saveWithPanel()
        }
    }
}
