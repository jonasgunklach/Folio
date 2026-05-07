// ContentEditorView.swift
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
import MuPDFKit

/// Inspector panel for direct PDF text editing backed by MuPDF.
struct ContentEditorView: View {

    var tab: DocumentTab
    @State private var viewModel = ContentEditorViewModel()
    @State private var extractedLines: [PDFTextLine] = []
    @State private var selectedLine: PDFTextLine?
    @State private var editingText: String = ""
    @State private var lastSuccessMessage: String?

    var body: some View {
        Form {
            // ── Text editing ─────────────────────────────────────────────────
            Section("Edit Text") {
                Button("Load Text Lines from Page \(tab.currentPageIndex + 1)") {
                    extractText()
                }
                .disabled(viewModel.isWorking || tab.url == nil)

                if viewModel.isWorking {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Working…").foregroundStyle(.secondary)
                    }
                }

                if let msg = lastSuccessMessage {
                    Label(msg, systemImage: "checkmark.circle")
                        .foregroundStyle(.green)
                        .font(.caption)
                }

                if !extractedLines.isEmpty {
                    Text("Tap a line below to edit it.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    ForEach(extractedLines) { line in
                        TextLineEditRow(
                            line: line,
                            isSelected: selectedLine?.id == line.id,
                            editingText: $editingText,
                            onSelect: {
                                selectedLine = line
                                editingText = line.text
                            },
                            onApply: { applyTextEdit(for: line) },
                            onCancel: {
                                selectedLine = nil
                                editingText = ""
                            },
                            isWorking: viewModel.isWorking
                        )
                    }
                }
            }

            // ── Errors ───────────────────────────────────────────────────────
            if let error = viewModel.lastError {
                Section {
                    Label(error.localizedDescription ?? "Unknown error",
                          systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                        .font(.caption)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .onChange(of: tab.currentPageIndex) {
            extractedLines = []
            selectedLine = nil
            editingText = ""
        }
    }

    // MARK: - Helpers

    private func extractText() {
        guard let fileURL = tab.url else { return }
        viewModel.extractTextLines(documentURL: fileURL,
                                   pageIndex: tab.currentPageIndex) { lines in
            extractedLines = lines
            selectedLine = nil
            editingText = ""
            lastSuccessMessage = nil
        }
    }

    private func applyTextEdit(for line: PDFTextLine) {
        guard let fileURL = tab.url else { return }
        let rect = CGRect(x: line.x, y: line.y, width: line.width, height: line.height)
        let newText = editingText
        lastSuccessMessage = nil
        viewModel.replaceText(newText,
                              documentURL: fileURL,
                              pageIndex: tab.currentPageIndex,
                              rect: rect,
                              fontName: line.fontName,
                              fontSize: line.fontSize,
                              colorR: line.colorR,
                              colorG: line.colorG,
                              colorB: line.colorB) { pdfData in
            // Load the MuPDF-modified bytes into PDFKit so the view refreshes.
            if let newDoc = PDFDocument(data: pdfData) {
                tab.document = newDoc
            }

            // Write the exact MuPDF bytes directly to disk in a background task
            // (bypasses PDFKit's dataRepresentation() so no round-trip risk).
            // If the write fails (e.g. old read-only bookmark), isModified stays
            // true and the user can File > Save As.
            tab.isModified = true
            Task.detached(priority: .userInitiated) {
                let accessing = fileURL.startAccessingSecurityScopedResource()
                defer { if accessing { fileURL.stopAccessingSecurityScopedResource() } }
                if (try? pdfData.write(to: fileURL)) != nil {
                    await MainActor.run { tab.isModified = false }
                }
                // On failure: tab.isModified stays true → Cmd+S → NSSavePanel.
            }

            // Optimistically update the text line in the sidebar list so the
            // user sees their edit immediately without re-reading from disk.
            extractedLines = extractedLines.map { l in
                guard l.id == line.id else { return l }
                return PDFTextLine(text: newText,
                                   x: l.x, y: l.y, width: l.width, height: l.height,
                                   fontName: l.fontName, fontSize: l.fontSize,
                                   colorR: l.colorR, colorG: l.colorG, colorB: l.colorB)
            }
            selectedLine = nil
            editingText = ""
            lastSuccessMessage = "Text updated."
        }
    }
}

// MARK: - Text line edit row

private struct TextLineEditRow: View {
    let line: PDFTextLine
    let isSelected: Bool
    @Binding var editingText: String
    let onSelect: () -> Void
    let onApply: () -> Void
    let onCancel: () -> Void
    let isWorking: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button(action: onSelect) {
                HStack {
                    Text(line.text)
                        .font(.caption)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if isSelected {
                        Image(systemName: "pencil.circle.fill")
                            .foregroundStyle(Color.accentColor)
                    }
                }
            }
            .buttonStyle(.plain)
            .padding(6)
            .background(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 6))

            if isSelected {
                TextField("Replacement text…", text: $editingText)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption)

                HStack {
                    Button("Apply", action: onApply)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .disabled(editingText.isEmpty || isWorking)

                    Button("Cancel", action: onCancel)
                        .controlSize(.small)
                }
            }
        }
    }
}
