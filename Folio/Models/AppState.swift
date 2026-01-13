// AppState.swift
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
import PDFKit

/// Central application state. Single source of truth for open documents, active tool,
/// and global UI visibility flags. Injected via `.environment(appState)`.
@MainActor
@Observable
final class AppState {

    // MARK: - Tabs

    var tabs: [DocumentTab] = []
    var activeTabID: UUID?

    // MARK: - UI State

    var isSidebarVisible: Bool = SettingsStore.shared.showSidebarByDefault
    var isAISidebarVisible: Bool = false
    var activeTool: ActiveTool = .select
    var isFileImporterPresented: Bool = false

    /// Set when a tab close is requested but the tab has unsaved changes.
    /// ContentView observes this to show a Save / Don't Save / Cancel alert.
    var tabPendingClose: DocumentTab? = nil

    // MARK: - Computed

    var activeTab: DocumentTab? {
        tabs.first { $0.id == activeTabID }
    }

    // MARK: - Document Management

    /// Opens a PDF at the given URL. If already open, activates that tab.
    func openDocument(at url: URL) {
        if let existing = tabs.first(where: { $0.url == url }) {
            activeTabID = existing.id
            return
        }

        let accessed = url.startAccessingSecurityScopedResource()
        guard let document = PDFDocument(url: url) else {
            if accessed { url.stopAccessingSecurityScopedResource() }
            return
        }
        // Keep the security scope open for the lifetime of this tab so Cmd+S can write.
        let tab = DocumentTab(document: document, url: url, securityScopeActive: accessed)
        tabs.append(tab)
        activeTabID = tab.id
    }

    /// Creates a new empty single-page PDF document in a new tab.
    func openEmptyDocument() {
        let document = PDFDocument()
        let page = PDFPage()
        document.insert(page, at: 0)
        let tab = DocumentTab(document: document)
        tabs.append(tab)
        activeTabID = tab.id
    }

    func closeTab(_ id: UUID) {
        if let tab = tabs.first(where: { $0.id == id }), tab.isModified {
            tabPendingClose = tab
            return
        }
        performCloseTab(id)
    }

    /// Actually removes the tab — call after save/discard decision.
    func performCloseTab(_ id: UUID) {
        if let tab = tabs.first(where: { $0.id == id }) {
            tab.releaseSecurityScope()
        }
        tabs.removeAll { $0.id == id }
        if activeTabID == id {
            activeTabID = tabs.last?.id
        }
        tabPendingClose = nil
    }

    func activateTab(_ id: UUID) {
        activeTabID = id
    }

    /// Saves the active tab to disk on a background thread.
    func saveActiveTab() {
        guard let tab = activeTab else { return }
        Task { await tab.save() }
    }

    func toggleSidebar() {
        isSidebarVisible.toggle()
    }
}
