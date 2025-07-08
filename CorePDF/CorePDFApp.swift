// CorePDFApp.swift
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

@main
struct CorePDFApp: App {

    @State private var appState = AppState()
    private let settings = SettingsStore.shared

    init() {
        // Disable macOS automatic window tab bar so our custom tab system
        // is the sole tab UI and "Show Tab Bar" never appears in the menu.
        NSWindow.allowsAutomaticWindowTabbing = false
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appState)
                .environment(settings)
                .frame(minWidth: 620, minHeight: 480)
                .preferredColorScheme(settings.appearanceMode.colorScheme)
        }
        .commands {
            // ── File ──────────────────────────────────────────────────
            CommandGroup(replacing: .newItem) {
                Button("Open PDF\u{2026}") { appState.isFileImporterPresented = true }
                    .keyboardShortcut("o")
                Button("New Empty Document") { appState.openEmptyDocument() }
                    .keyboardShortcut("n")
                Menu("New Tab") {
                    Button("Open PDF\u{2026}") { appState.isFileImporterPresented = true }
                    Button("New Empty Document") { appState.openEmptyDocument() }
                }
                .keyboardShortcut("t")
            }

            CommandGroup(after: .newItem) {
                Button("Close Tab") {
                    if let tab = appState.activeTab { appState.closeTab(tab.id) }
                }
                .keyboardShortcut("w")
                .disabled(appState.activeTab == nil)
            }

            CommandGroup(replacing: .saveItem) {
                Button("Save") { appState.saveActiveTab() }
                    .keyboardShortcut("s")
                    .disabled(!(appState.activeTab?.isModified ?? false) || (appState.activeTab?.isSaving ?? false))
            }

            // ── View – Zoom ───────────────────────────────────────────
            CommandGroup(after: .toolbar) {
                Divider()
                Button("Zoom In")      { appState.activeTab?.viewerViewModel.zoomIn()    }
                    .keyboardShortcut("=")
                Button("Zoom Out")     { appState.activeTab?.viewerViewModel.zoomOut()   }
                    .keyboardShortcut("-")
                Button("Actual Size")  { appState.activeTab?.viewerViewModel.zoomToFit() }
                    .keyboardShortcut("0")
                Divider()
                Button("Toggle Sidebar") {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
                        appState.isSidebarVisible.toggle()
                    }
                }
                .keyboardShortcut("s", modifiers: [.command, .shift])
                Divider()
                Button("Scroll View") {
                    appState.activeTab?.viewMode = .scroll
                }
                .keyboardShortcut("1", modifiers: [.command, .shift])
                .disabled(appState.activeTab == nil)
                Button("Page Grid") {
                    appState.activeTab?.viewMode = .grid
                }
                .keyboardShortcut("2", modifiers: [.command, .shift])
                .disabled(appState.activeTab == nil)
            }

            // ── Window – Tab switching (⌘1 … ⌘9) ─────────────────────
            CommandGroup(before: .windowList) {
                ForEach(Array(appState.tabs.prefix(9).enumerated()), id: \.element.id) { i, tab in
                    Button(tab.title) { appState.activateTab(tab.id) }
                        .keyboardShortcut(KeyEquivalent(Character(String(i + 1))),
                                          modifiers: .command)
                }
                if !appState.tabs.isEmpty { Divider() }
            }
        }
        .windowToolbarStyle(.unified(showsTitle: false))
        .defaultSize(width: 1200, height: 800)

        Settings {
            SettingsView()
                .environment(settings)
        }
    }
}
