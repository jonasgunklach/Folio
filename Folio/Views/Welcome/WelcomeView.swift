// WelcomeView.swift
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

/// Empty-state drop zone shown when no documents are open.
/// Top half: drag-and-drop / open button.  Bottom half: recently opened files.
struct WelcomeView: View {

    @Environment(AppState.self) private var appState
    @State private var isDropTargeted = false

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {

                // ── Top 50 %: Open a file ──────────────────────────────
                openSection
                    .frame(height: geo.size.height / 2)

                Divider()

                // ── Bottom 50 %: Recent files ──────────────────────────
                recentSection
                    .frame(height: geo.size.height / 2)
            }
        }
        .background(.background)
    }

    // MARK: - Open section

    private var openSection: some View {
        VStack(spacing: 20) {
            Image(systemName: "doc.viewfinder")
                .symbolRenderingMode(.multicolor)
                .font(.system(size: 56))
                .foregroundStyle(.secondary)

            VStack(spacing: 6) {
                Text("Open a PDF")
                    .font(.title2.bold())
                Text("Drop a file here, or click to browse.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Button("Choose File…") {
                appState.isFileImporterPresented = true
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(
                    isDropTargeted ? Color.accentColor : Color.secondary.opacity(0.3),
                    style: StrokeStyle(lineWidth: 2, dash: [6, 4])
                )
                .padding(32)
        }
        .contentShape(Rectangle())
        .dropDestination(for: URL.self) { urls, _ in
            urls.filter { $0.pathExtension.lowercased() == "pdf" }
                .forEach { appState.openDocument(at: $0) }
            return true
        } isTargeted: { targeted in
            withAnimation(.easeInOut(duration: 0.2)) {
                isDropTargeted = targeted
            }
        }
    }

    // MARK: - Recent files section

    private var recentSection: some View {
        let recent = SettingsStore.shared.recentFileURLs
        return VStack(alignment: .leading, spacing: 0) {
            Text("Recent Files")
                .font(.headline)
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 10)

            if recent.isEmpty {
                Spacer()
                Text("No recently opened files")
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity)
                Spacer()
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 14) {
                        ForEach(recent, id: \.self) { url in
                            RecentFileCard(url: url) {
                                appState.openDocument(at: url)
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 16)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - Recent file card

private struct RecentFileCard: View {
    let url: URL
    let action: () -> Void

    @State private var thumbnail: NSImage?
    @State private var isHovered = false

    private var displayName: String {
        url.deletingPathExtension().lastPathComponent
    }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                // Thumbnail frame
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.secondary.opacity(0.08))

                    if let thumb = thumbnail {
                        Image(nsImage: thumb)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    } else {
                        Image(systemName: "doc.text")
                            .font(.system(size: 28))
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 96, height: 124)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(isHovered ? Color.accentColor : Color.secondary.opacity(0.25),
                                lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.08), radius: 4, y: 2)

                // File name
                Text(displayName)
                    .font(.caption)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(width: 96, alignment: .leading)
            }
        }
        .buttonStyle(.plain)
        .scaleEffect(isHovered ? 1.03 : 1.0)
        .animation(.easeOut(duration: 0.15), value: isHovered)
        .onHover { isHovered = $0 }
        .task(id: url) {
            thumbnail = await makeThumbnail(for: url)
        }
    }

    private func makeThumbnail(for url: URL) async -> NSImage? {
        await Task.detached(priority: .utility) {
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }
            guard let doc = PDFDocument(url: url),
                  let page = doc.page(at: 0) else { return nil }
            return page.thumbnail(of: CGSize(width: 192, height: 248), for: .mediaBox)
        }.value
    }
}

