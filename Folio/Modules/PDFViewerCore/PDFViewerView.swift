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
    @State private var contentEditorVM = ContentEditorViewModel()

    // Inline text editing state (editText tool)
    @State private var inlineEditLine: PDFTextLine? = nil
    @State private var inlineEditText: String = ""
    /// Rect of the tapped line in PDFView (NSView) coordinates: origin bottom-left, Y up.
    @State private var inlineEditViewRect: CGRect = .zero

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
                annotationViewModel: tab.annotationViewModel,
                onAnnotationAdded: { tab.isModified = true },
                undoManager: tab.undoManager,
                onPlacementDone: {
                    appState.activeTool = .select
                },
                onImageDropped: nil,
                onTextLineTapped: { line, viewRect in
                    inlineEditLine = line
                    inlineEditText = line.text
                    inlineEditViewRect = viewRect
                }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .topLeading) {
                // Inline text editor — shown when editText tool taps a line.
                // The editor floats over the PDF exactly at the tapped line's position.
                if let line = inlineEditLine {
                    GeometryReader { geo in
                        // Convert NSView coords (origin BL, Y up) → SwiftUI (origin TL, Y down).
                        let swiftUIY = geo.size.height - inlineEditViewRect.maxY
                        let scaledSize = line.fontSize * tab.viewerViewModel.scaleFactor
                        let lineColor = NSColor(
                            red:   CGFloat(line.colorR),
                            green: CGFloat(line.colorG),
                            blue:  CGFloat(line.colorB),
                            alpha: 1.0
                        )
                        let isMultiLine = line.height > line.fontSize * 1.8
                        InlineTextEditorOverlay(
                            text: $inlineEditText,
                            fontSize: scaledSize,
                            fontName: line.fontName,
                            textColor: lineColor,
                            isMultiLine: isMultiLine,
                            onCommit: applyInlineEdit,
                            onCancel: dismissInlineEditor
                        )
                        .frame(
                            width:  max(inlineEditViewRect.width,  scaledSize * 3),
                            height: max(inlineEditViewRect.height, scaledSize * 1.5)
                        )
                        .background(
                            RoundedRectangle(cornerRadius: 2)
                                .fill(.white.opacity(0.95))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 2)
                                        .stroke(Color.accentColor, lineWidth: 1.5)
                                )
                        )
                        .offset(x: inlineEditViewRect.minX, y: swiftUIY)
                    }
                }
            }

            // Annotation colour/settings palette — appears when an annotation tool
            // is active, OR when a shape annotation is selected in select mode.
            if let paletteTool = effectivePaletteTool {
                AnnotationToolPaletteView(
                    viewModel: tab.annotationViewModel,
                    activeTool: paletteTool
                )
                .padding(.bottom, 16)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.28, dampingFraction: 0.8), value: appState.activeTool)
        .onChange(of: appState.activeTool) {
            // Clear shape selection when the user switches away from select tool
            // so the palette hides and the next tool starts fresh.
            if appState.activeTool != .select {
                tab.annotationViewModel.deselectAnnotation()
            }
            // Dismiss the inline editor when leaving the editText tool.
            if appState.activeTool != .editText {
                dismissInlineEditor()
            }
        }
        .onDisappear { tab.viewerViewModel.stopTTS() }
    }

    /// The tool to use for the floating palette, or nil when the palette should be hidden.
    private var effectivePaletteTool: ActiveTool? {
        // editText has no annotation palette.
        if appState.activeTool.isAnnotationTool && appState.activeTool != .editText { return appState.activeTool }
        // In select mode, show the shape palette when a shape annotation is selected.
        if appState.activeTool == .select,
           let ann = tab.annotationViewModel.selectedAnnotation {
            switch ann.type {
            case "Square", "Circle", "Line": return .shape
            default: break
            }
        }
        return nil
    }

    // MARK: - Inline text edit

    private func applyInlineEdit() {
        guard let line = inlineEditLine, let fileURL = tab.url else {
            dismissInlineEditor()
            return
        }
        let rect    = CGRect(x: line.x, y: line.y, width: line.width, height: line.height)
        let newText = inlineEditText
        dismissInlineEditor()  // close overlay before async work begins
        contentEditorVM.replaceText(
            newText, documentURL: fileURL,
            pageIndex: tab.currentPageIndex,
            rect: rect, fontName: line.fontName, fontSize: line.fontSize,
            colorR: line.colorR, colorG: line.colorG, colorB: line.colorB
        ) { [tab] pdfData in
            if let newDoc = PDFDocument(data: pdfData) { tab.document = newDoc }
            tab.isModified = true
            Task.detached(priority: .userInitiated) {
                let accessing = fileURL.startAccessingSecurityScopedResource()
                defer { if accessing { fileURL.stopAccessingSecurityScopedResource() } }
                if (try? pdfData.write(to: fileURL)) != nil {
                    await MainActor.run { tab.isModified = false }
                }
            }
        }
    }

    private func dismissInlineEditor() {
        inlineEditLine    = nil
        inlineEditText    = ""
        inlineEditViewRect = .zero
    }
}
