// PDFKitView.swift
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

/// `NSViewRepresentable` bridge for PDFKit's `PDFView`.
///
/// Handles:
/// - Continuous vertical / horizontal scrolling
/// - Reading modes (Default, Night, Sepia) via CIFilter on the layer
/// - Two-way binding for scale factor and current page index
/// - Annotation application on text selection based on `activeTool`
/// - Zoom sync from trackpad pinch and Cmd+−/= via `PDFViewScaleChanged`
/// - Comment (text) annotations via click gesture
struct PDFKitView: NSViewRepresentable {

    let document: PDFDocument
    let readingMode: ReadingMode
    let displayMode: PDFDisplayMode
    let displayDirection: PDFDisplayDirection
    @Binding var scaleFactor: CGFloat
    @Binding var currentPageIndex: Int

    // Annotation settings
    let activeTool: ActiveTool
    let highlightColor: NSColor
    let underlineColor: NSColor
    let strikethroughColor: NSColor
    let annotationOpacity: CGFloat
    var onAnnotationAdded: () -> Void

    // MARK: - NSViewRepresentable

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.document = document
        pdfView.autoScales = true
        pdfView.displayMode = displayMode
        pdfView.displayDirection = displayDirection
        pdfView.displaysPageBreaks = true
        pdfView.displaysAsBook = false
        pdfView.enableDataDetectors = true
        pdfView.delegate = context.coordinator

        let nc = NotificationCenter.default
        nc.addObserver(context.coordinator,
                       selector: #selector(Coordinator.handlePageChange(_:)),
                       name: .PDFViewPageChanged, object: pdfView)
        // Sync zoom from trackpad pinch and Cmd+−/=
        nc.addObserver(context.coordinator,
                       selector: #selector(Coordinator.handleScaleChange(_:)),
                       name: .PDFViewScaleChanged, object: pdfView)
        // Apply annotation when user finishes selecting text with an annotation tool.
        // We monitor mouseUp rather than PDFViewSelectionChanged so the annotation is
        // added exactly once — not on every intermediate drag event.
        context.coordinator.installMouseUpMonitor(for: pdfView)

        // Click gesture for adding comment/text annotations
        let click = NSClickGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleClick(_:)))
        click.delaysPrimaryMouseButtonEvents = false
        pdfView.addGestureRecognizer(click)

        applyReadingMode(readingMode, to: pdfView)
        return pdfView
    }

    func updateNSView(_ pdfView: PDFView, context: Context) {
        // Keep coordinator in sync with the latest struct values
        context.coordinator.parent = self

        if pdfView.document !== document { pdfView.document = document }
        pdfView.displayMode = displayMode
        pdfView.displayDirection = displayDirection

        if abs(pdfView.scaleFactor - scaleFactor) > 0.001 {
            pdfView.scaleFactor = scaleFactor
        }

        applyReadingMode(readingMode, to: pdfView)

        if let targetPage = document.page(at: currentPageIndex),
           pdfView.currentPage !== targetPage {
            pdfView.go(to: targetPage)
        }
    }

    // MARK: - Reading Mode

    private func applyReadingMode(_ mode: ReadingMode, to pdfView: PDFView) {
        pdfView.wantsLayer = true
        switch mode {
        case .default:
            pdfView.backgroundColor = .windowBackgroundColor
            pdfView.layer?.filters = nil
        case .night:
            pdfView.backgroundColor = .black
            if let filter = CIFilter(name: "CIColorInvert") {
                pdfView.layer?.filters = [filter]
            }
        case .sepia:
            pdfView.backgroundColor = NSColor(red: 0.96, green: 0.93, blue: 0.82, alpha: 1)
            if let filter = CIFilter(name: "CISepiaTone") {
                filter.setValue(0.75, forKey: kCIInputIntensityKey)
                pdfView.layer?.filters = [filter]
            }
        }
    }

    // MARK: - Coordinator

    @MainActor
    final class Coordinator: NSObject, PDFViewDelegate {

        var parent: PDFKitView

        init(_ parent: PDFKitView) { self.parent = parent }

        // MARK: Page change

        @objc func handlePageChange(_ notification: Notification) {
            guard let pdfView = notification.object as? PDFView,
                  let currentPage = pdfView.currentPage,
                  let document = pdfView.document else { return }
            let index = document.index(for: currentPage)
            guard index != NSNotFound else { return }
            if parent.currentPageIndex != index { parent.currentPageIndex = index }
        }

        // MARK: Scale change (trackpad pinch, Cmd+−/=)

        @objc func handleScaleChange(_ notification: Notification) {
            guard let pdfView = notification.object as? PDFView else { return }
            let scale = pdfView.scaleFactor
            if abs(parent.scaleFactor - scale) > 0.001 {
                parent.scaleFactor = scale
            }
        }

        // MARK: Mouse-up → apply annotation

        private var mouseUpMonitor: Any?
        private weak var monitoredPDFView: PDFView?

        func installMouseUpMonitor(for pdfView: PDFView) {
            monitoredPDFView = pdfView
            mouseUpMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseUp) { [weak self] event in
                self?.applyAnnotationIfNeeded()
                return event
            }
        }

        private func applyAnnotationIfNeeded() {
            guard let pdfView = monitoredPDFView,
                  let selection = pdfView.currentSelection,
                  !(selection.string ?? "").isEmpty else { return }

            let tool = parent.activeTool
            guard tool == .highlight || tool == .underline || tool == .strikethrough else { return }

            selection.pages.forEach { page in
                let bounds = selection.bounds(for: page)
                let type: PDFAnnotationSubtype
                switch tool {
                case .highlight:     type = .highlight
                case .underline:     type = .underline
                case .strikethrough: type = .strikeOut
                default: return
                }
                let ann = PDFAnnotation(bounds: bounds, forType: type, withProperties: nil)
                switch tool {
                case .highlight:
                    // PDFKit draws the highlight at full color; use alpha for opacity
                    ann.color = parent.highlightColor.withAlphaComponent(parent.annotationOpacity)
                case .underline:
                    ann.color = parent.underlineColor
                case .strikethrough:
                    ann.color = parent.strikethroughColor
                default: break
                }
                page.addAnnotation(ann)
            }
            pdfView.clearSelection()
            parent.onAnnotationAdded()
        }

        deinit {
            if let monitor = mouseUpMonitor {
                NSEvent.removeMonitor(monitor)
            }
        }

        // MARK: Click → add comment annotation

        @objc func handleClick(_ recognizer: NSClickGestureRecognizer) {
            guard parent.activeTool == .text,
                  let pdfView = recognizer.view as? PDFView else { return }

            let location = recognizer.location(in: pdfView)
            guard let page = pdfView.page(for: location, nearest: true) else { return }
            let pagePoint = pdfView.convert(location, to: page)

            // Use NSAlert as a simple inline text-entry panel
            let alert = NSAlert()
            alert.messageText = "Add Comment"
            alert.informativeText = "Type a note for this location:"
            let tf = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
            tf.placeholderString = "Your comment…"
            alert.accessoryView = tf
            alert.addButton(withTitle: "Add")
            alert.addButton(withTitle: "Cancel")
            alert.window.initialFirstResponder = tf

            guard alert.runModal() == .alertFirstButtonReturn else { return }
            let text = tf.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return }

            let noteBounds = CGRect(x: pagePoint.x - 16, y: pagePoint.y - 16,
                                    width: 32, height: 32)
            let ann = PDFAnnotation(bounds: noteBounds, forType: .text, withProperties: nil)
            ann.contents = text
            ann.color = .systemYellow
            page.addAnnotation(ann)
            parent.onAnnotationAdded()
        }
    }
}

