// PDFViewerView.swift
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

/// SwiftUI wrapper that composes `PDFKitView` with the per-document `PDFViewerViewModel`
/// stored on `DocumentTab`. One instance is created per open tab; keyed on tab ID.
struct PDFViewerView: View {

    var tab: DocumentTab
    @Environment(AppState.self) private var appState

    var body: some View {
        ZStack(alignment: .bottom) {
            PDFKitView(
                document: tab.document,
                readingMode: tab.readingMode,
                displayMode: tab.viewerViewModel.displayMode,
                displayDirection: tab.viewerViewModel.displayDirection,
                scaleFactor: Binding(
                    get: { tab.viewerViewModel.scaleFactor },
                    set: { tab.viewerViewModel.setScale($0) }
                ),
                currentPageIndex: Binding(
                    get: { tab.currentPageIndex },
                    set: { tab.currentPageIndex = $0 }
                ),
                activeTool: appState.activeTool,
                highlightColor: tab.annotationViewModel.highlightColor,
                underlineColor: tab.annotationViewModel.underlineColor,
                strikethroughColor: tab.annotationViewModel.strikethroughColor,
                annotationOpacity: tab.annotationViewModel.highlightOpacity,
                onAnnotationAdded: { tab.isModified = true }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Annotation colour/settings palette — appears when annotation tool is active
            if appState.activeTool.isAnnotationTool {
                AnnotationToolPaletteView(
                    viewModel: tab.annotationViewModel,
                    activeTool: appState.activeTool
                )
                .padding(.bottom, 16)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.28, dampingFraction: 0.8), value: appState.activeTool)
        .onDisappear { tab.viewerViewModel.stopTTS() }
    }
}

