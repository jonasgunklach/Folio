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

/// Inspector panel for direct content editing operations (text, images, links).
/// Presented as a sheet or sidebar panel in a future iteration.
struct ContentEditorView: View {

    var tab: DocumentTab
    @State private var viewModel = ContentEditorViewModel()
    @State private var linkURL: String = ""

    var body: some View {
        Form {
            Section("Text Editing") {
                LabeledContent("Status") {
                    Text("Core Text pipeline — coming soon")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
            }

            Section("Insert Hyperlink") {
                TextField("https://example.com", text: $linkURL)
                    .textFieldStyle(.roundedBorder)

                Button("Insert on Current Page") {
                    guard let page = tab.document.page(at: tab.currentPageIndex) else { return }
                    // TODO: Use a selection rect from the PDF canvas
                    let placeholderBounds = CGRect(x: 100, y: 100, width: 200, height: 20)
                    viewModel.insertLink(urlString: linkURL, on: page, bounds: placeholderBounds)
                    linkURL = ""
                }
                .disabled(linkURL.isEmpty)
            }

            Section("Images") {
                Button("Extract Images from Page") {
                    guard let page = tab.document.page(at: tab.currentPageIndex) else { return }
                    _ = viewModel.extractImages(from: page)
                }

                Button("Insert Image…") {
                    // TODO: Drive NSOpenPanel then call viewModel.insertImage
                }
            }

            if let error = viewModel.lastError {
                Section {
                    Text(error.localizedDescription)
                        .foregroundStyle(.red)
                        .font(.caption)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}
