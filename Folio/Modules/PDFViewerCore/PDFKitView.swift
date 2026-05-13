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
    let annotationViewModel: AnnotationManagerViewModel
    var onAnnotationAdded: () -> Void
    var undoManager: UndoManager
    /// Called after a single-shot placement tool (text, addText, shape, signature)
    /// finishes placing its annotation.  Use to switch back to the select tool.
    var onPlacementDone: (() -> Void)?
    var onImageDropped: ((NSImage, PDFPage, CGRect) -> Void)?
    /// Called when the editText tool is active and the user clicks on a text line.
    /// Passes the tapped `PDFTextLine` and its rect in PDFView (NSView) coordinates
    /// (origin bottom-left, Y increases upward) so the caller can position an overlay.
    var onTextLineTapped: ((PDFTextLine, CGRect) -> Void)?

    // MARK: - NSViewRepresentable

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> PDFView {
        let pdfView = DrawablePDFView()
        pdfView.coordinator = context.coordinator
        pdfView.document = document
        pdfView.autoScales = true
        pdfView.displayMode = displayMode
        pdfView.displayDirection = displayDirection
        pdfView.displaysPageBreaks = true
        pdfView.displaysAsBook = false
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
        context.coordinator.installCursorMonitor(for: pdfView)
        context.coordinator.installCommentAndSignatureMonitor(for: pdfView)
        context.coordinator.installResizeOverlay(for: pdfView)
        pdfView.enableImageDrop(handler: onImageDropped)

        applyReadingMode(readingMode, to: pdfView)
        return pdfView
    }

    func updateNSView(_ pdfView: PDFView, context: Context) {
        // Keep coordinator in sync with the latest struct values
        context.coordinator.parent = self
        if let drawable = pdfView as? DrawablePDFView {
            drawable.enableImageDrop(handler: onImageDropped)
        }
        pdfView.window?.invalidateCursorRects(for: pdfView)
        pdfView.window?.acceptsMouseMovedEvents = true

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
        context.coordinator.refreshOverlay()
    }

    // MARK: - Reading Mode

    private func applyReadingMode(_ mode: ReadingMode, to pdfView: PDFView) {
        pdfView.wantsLayer = true
        switch mode {
        case .default:
            pdfView.backgroundColor = .windowBackgroundColor
            pdfView.layer?.filters = nil
        case .night:
            // CIColorInvert is applied to the entire layer, including the background.
            // Setting backgroundColor = .black would make it invert to white.
            // Use .white so it inverts to black, matching the dark inverted content.
            pdfView.backgroundColor = .white
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

        // MARK: Mouse-up → apply text-selection annotation

        private var mouseUpMonitor: Any?
        private weak var monitoredPDFView: PDFView?

        func installMouseUpMonitor(for pdfView: PDFView) {
            monitoredPDFView = pdfView
            mouseUpMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseUp) { [weak self] event in
                self?.applyAnnotationIfNeeded()
                return event
            }
        }

        // MARK: Cursor override for text-selection annotation tools

        private var cursorMonitor: Any?
        private weak var cursorPDFView: DrawablePDFView?

        fileprivate func installCursorMonitor(for pdfView: DrawablePDFView) {
            cursorPDFView = pdfView
            // Force I-beam cursor in text-selection annotation modes so PDFKit's
            // link cursor doesn't show up over hyperlinks.
            cursorMonitor = NSEvent.addLocalMonitorForEvents(
                matching: [.mouseMoved, .leftMouseDragged]
            ) { [weak self] event in
                guard let self, let pv = self.cursorPDFView,
                      event.window === pv.window else { return event }
                let tool = self.parent.activeTool
                guard tool.isMarkupTool || tool == .editText else { return event }
                let viewPoint = pv.convert(event.locationInWindow, from: nil)
                guard pv.bounds.contains(viewPoint) else { return event }
                // Don't force cursor when hovering over a sibling view (e.g. the palette).
                if let hit = pv.window?.contentView?.hitTest(event.locationInWindow),
                   hit !== pv, !hit.isDescendant(of: pv) { return event }
                DispatchQueue.main.async { NSCursor.iBeam.set() }
                return event
            }
        }

        private func applyAnnotationIfNeeded() {
            guard let pdfView = monitoredPDFView,
                  let selection = pdfView.currentSelection,
                  !(selection.string ?? "").isEmpty else { return }

            let tool = parent.activeTool
            guard tool.isMarkupTool else { return }

            // Resolve the effective sub-tool
            let effectiveTool: ActiveTool
            if tool == .markup {
                effectiveTool = {
                    switch parent.annotationViewModel.markupSubtool {
                    case .highlight:    return .highlight
                    case .underline:    return .underline
                    case .strikethrough: return .strikethrough
                    }
                }()
            } else {
                effectiveTool = tool
            }

            // Iterate per-line selections so each annotation covers exactly one line of text
            let lineSelections = selection.selectionsByLine()
            for lineSel in lineSelections {
                for page in lineSel.pages {
                    let bounds = lineSel.bounds(for: page)
                    guard !bounds.isEmpty else { continue }
                    let annType: PDFAnnotationSubtype
                    switch effectiveTool {
                    case .highlight:     annType = .highlight
                    case .underline:     annType = .underline
                    case .strikethrough: annType = .strikeOut
                    default: continue
                    }
                    let ann = PDFAnnotation(bounds: bounds, forType: annType, withProperties: nil)
                    switch effectiveTool {
                    case .highlight:
                        ann.color = parent.highlightColor.withAlphaComponent(parent.annotationOpacity)
                    case .underline:
                        ann.color = parent.underlineColor
                    case .strikethrough:
                        ann.color = parent.strikethroughColor
                    default: break
                    }
                    page.addAnnotation(ann)
                    trackAnnotationAdd(ann, on: page)
                }
            }
            pdfView.clearSelection()
            parent.onAnnotationAdded()
        }

        deinit {
            if let monitor = mouseUpMonitor  { NSEvent.removeMonitor(monitor) }
            if let m = commentSigMonitor     { NSEvent.removeMonitor(m) }
            if let m = cursorMonitor         { NSEvent.removeMonitor(m) }
        }

        // MARK: - Undo support

        /// Registers an undo entry for an annotation that was just added to `page`.
        /// Call immediately after every permanent `page.addAnnotation(_:)`.
        /// NSUndoManager auto-groups registrations within the same run-loop turn,
        /// so a multi-annotation markup stroke is undone as a single Cmd+Z step.
        func trackAnnotationAdd(_ ann: PDFAnnotation, on page: PDFPage) {
            parent.undoManager.registerUndo(withTarget: self) { [weak page] coord in
                guard let page else { return }
                page.removeAnnotation(ann)
                // Re-register so Cmd+Shift+Z re-adds the annotation.
                // NSUndoManager treats this call as "redo" while isUndoing==true.
                coord.trackAnnotationAdd(ann, on: page)
                coord.parent.onAnnotationAdded()
            }
        }

        // MARK: - Resize overlay

        private var resizeOverlay: AnnotationResizeOverlay?
        private weak var overlayPDFView: PDFView?

        func installResizeOverlay(for pdfView: PDFView) {
            overlayPDFView = pdfView
            let overlay = AnnotationResizeOverlay(frame: pdfView.bounds)
            overlay.autoresizingMask = [.width, .height]
            overlay.wantsLayer = true
            overlay.isHidden   = true
            overlay.onChanged  = { [weak self] in
                self?.parent.onAnnotationAdded()
            }
            // Add as a direct full-frame subview of PDFView so it shares the same
            // coordinate space and is automatically clipped/scrolled with it.
            pdfView.addSubview(overlay, positioned: .above, relativeTo: nil)
            resizeOverlay = overlay
        }

        func refreshOverlay() {
            guard let pv = overlayPDFView, let ov = resizeOverlay else { return }
            ov.refreshFrame(pdfView: pv)
        }

        func selectAnnotationForResize(_ ann: PDFAnnotation) {
            guard let pv = overlayPDFView, let ov = resizeOverlay else { return }
            ov.select(ann, pdfView: pv)
            // Dispatch async so SwiftUI layout passes that follow the mouse-up
            // event (e.g. activeTool change from onPlacementDone) cannot steal
            // first responder before the user presses Delete.
            DispatchQueue.main.async { ov.window?.makeFirstResponder(ov) }
        }

        func deselectAnnotationResize() {
            resizeOverlay?.deselect()
            parent.annotationViewModel.deselectAnnotation()
        }

        /// Called by DrawablePDFView when an image is dropped onto the canvas.
        /// Creates a PDFImageAnnotation on the correct page and immediately selects it.
        func dropImage(_ image: NSImage, on page: PDFPage, at rect: CGRect) {
            let ann = PDFImageAnnotation(image: image, bounds: rect)
            page.addAnnotation(ann)
            trackAnnotationAdd(ann, on: page)
            selectAnnotationForResize(ann)
            parent.onAnnotationAdded()
        }

        // MARK: - Comment + Signature / shape drag — unified event monitor

        private var commentSigMonitor: Any?
        private weak var commentSigPDFView: DrawablePDFView?

        // Drag state for shape drawing
        private var shapeDragStart: CGPoint?    // in page coords
        private var shapeDragPage:  PDFPage?
        private var shapePreviewAnn: PDFAnnotation?

        fileprivate func installCommentAndSignatureMonitor(for pdfView: DrawablePDFView) {
            commentSigPDFView = pdfView
            // Mouse-down: begin action
            commentSigMonitor = NSEvent.addLocalMonitorForEvents(
                matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]
            ) { [weak self] event in
                guard let self, let pv = self.commentSigPDFView else { return event }
                guard event.window === pv.window else { return event }
                let viewPoint = pv.convert(event.locationInWindow, from: nil)
                guard pv.bounds.contains(viewPoint) else { return event }

                // Don't steal clicks from sibling SwiftUI views (palette, toolbars).
                // AppKit hitTest traverses real NSView descendants; SwiftUI-only content
                // returns the NSHostingView, which is NOT a descendant of pv.
                if let hitView = pv.window?.contentView?.hitTest(event.locationInWindow),
                   hitView !== pv, !hitView.isDescendant(of: pv) {
                    return event
                }

                switch event.type {
                case .leftMouseDown:
                    return self.handleMouseDown(event: event, pv: pv, viewPoint: viewPoint)
                case .leftMouseDragged:
                    return self.handleMouseDragged(event: event, pv: pv, viewPoint: viewPoint)
                case .leftMouseUp:
                    return self.handleMouseUp(event: event, pv: pv, viewPoint: viewPoint)
                default:
                    return event
                }
            }
        }

        // MARK: - Text line hit-testing (editText tool)

        /// Returns the text line from `lines` nearest to `point` (in page coordinates).
        private func nearestLine(to point: CGPoint, in lines: [PDFTextLine]) -> PDFTextLine? {
            lines.min { distanceFromPoint(point, toRect: $0.bounds) < distanceFromPoint(point, toRect: $1.bounds) }
        }

        private func distanceFromPoint(_ point: CGPoint, toRect rect: CGRect) -> CGFloat {
            let dx = max(rect.minX - point.x, 0, point.x - rect.maxX)
            let dy = max(rect.minY - point.y, 0, point.y - rect.maxY)
            return hypot(dx, dy)
        }

        private func handleMouseDown(event: NSEvent, pv: DrawablePDFView, viewPoint: CGPoint) -> NSEvent? {
            // If the resize overlay is active, let it handle events on its own hit area
            // regardless of the currently active tool.  This makes placed annotations
            // always draggable/resizable without needing to first switch to select.
            // Skip pass-through on double-clicks so edit popovers can fire.
            if let overlay = resizeOverlay, !overlay.isHidden, event.clickCount < 2 {
                let ovPt = overlay.convert(event.locationInWindow, from: nil)
                if overlay.hitTest(ovPt) != nil {
                    return event   // pass through to overlay.mouseDown
                }
            }

            switch self.parent.activeTool {
            case .text:
                pv.showStickyPopover(at: viewPoint, coordinator: self,
                                     existingAnnotation: nil, viewOnly: false)
                return nil

            case .stamp:
                guard let page = pv.page(for: viewPoint, nearest: true) else { return event }
                let pp = pv.convert(viewPoint, to: page)
                guard let template = self.parent.annotationViewModel.selectedStamp else { return event }
                self.parent.annotationViewModel.addStamp(template, on: page, at: pp)
                self.parent.onAnnotationAdded()
                return nil

            case .addText:
                guard let page = pv.page(for: viewPoint, nearest: true) else { return event }
                let pp = pv.convert(viewPoint, to: page)
                let newTextAnn = self.parent.annotationViewModel.addTextBox(at: pp, on: page)
                self.trackAnnotationAdd(newTextAnn, on: page)
                self.selectAnnotationForResize(newTextAnn)
                self.parent.onAnnotationAdded()
                self.parent.onPlacementDone?()
                return nil

            case .shape:
                guard let page = pv.page(for: viewPoint, nearest: true) else { return event }
                let pp = pv.convert(viewPoint, to: page)
                shapeDragStart = pp
                shapeDragPage  = page
                return nil

            case .select:
                if let page = pv.page(for: viewPoint, nearest: false) {
                    let pp = pv.convert(viewPoint, to: page)
                    let resizableTypes: Set<String> = [
                        "FreeText", "Square", "Circle", "Line", "Stamp", "Ink", "Widget"
                    ]

                    // Double-click on a freeText → edit it
                    if event.clickCount == 2,
                       let ann = page.annotations.first(where: {
                           $0.type == "FreeText" && $0.bounds.insetBy(dx: -6, dy: -6).contains(pp)
                       }) {
                        let folioType = ann.value(forAnnotationKey: PDFAnnotationKey(rawValue: "/FolioType")) as? String
                        if folioType == "signature" {
                            // Re-open the signature editor pre-filled with current text
                            pv.showSignatureEditPopover(at: viewPoint, annotation: ann,
                                                        pagePoint: pp, page: page, coordinator: self)
                        } else {
                            // Generic text box editor
                            pv.showTextBoxEditPopover(at: viewPoint, annotation: ann)
                        }
                        return nil
                    }

                    // Single-click: select for resize or show comment popover
                    deselectAnnotationResize()
                    let hitAnn = page.annotations.first(where: {
                        let ft = $0.value(forAnnotationKey: PDFAnnotationKey(rawValue: "/FolioType")) as? String
                        guard ft != "comment" else { return false }   // comments handled below
                        return $0.bounds.insetBy(dx: -6, dy: -6).contains(pp)
                            && ($0.type.map { resizableTypes.contains($0) } ?? false)
                    })
                    if let ann = hitAnn {
                        self.selectAnnotationForResize(ann)
                        // Load annotation properties into the palette view model
                        // so ShapePaletteControls reflects the current annotation style.
                        let folioType = ann.value(forAnnotationKey: PDFAnnotationKey(rawValue: "/FolioType")) as? String
                        let isShape = (ann.type.map { ["Square", "Circle", "Line"].contains($0) } ?? false)
                                       || folioType == "line"
                        if isShape {
                            self.parent.annotationViewModel.selectAnnotation(ann)
                        }
                        return nil
                    }
                    if let ann = page.annotations.first(where: {
                        let folioType = $0.value(forAnnotationKey: PDFAnnotationKey(rawValue: "/FolioType")) as? String
                        let isComment = ($0.type == "Text") ||
                                        (folioType == "comment")
                        return isComment && $0.bounds.insetBy(dx: -6, dy: -6).contains(pp)
                    }) {
                        pv.showStickyPopover(at: viewPoint, coordinator: self,
                                             existingAnnotation: ann, viewOnly: true)
                        return nil
                    }
                } else {
                    deselectAnnotationResize()
                }
                return event

            case .editText:
                guard let page = pv.page(for: viewPoint, nearest: false) else { return event }
                let pagePoint = pv.convert(viewPoint, to: page)

                // Resolve font/colour at the exact click position.
                let attrStr = page.attributedString ?? NSAttributedString()
                guard attrStr.length > 0 else { return event }
                let charIdx  = max(0, min(page.characterIndex(at: pagePoint), attrStr.length - 1))
                let font     = attrStr.attribute(.font,            at: charIdx, effectiveRange: nil) as? NSFont  ?? NSFont.systemFont(ofSize: 12)
                let rawColor = attrStr.attribute(.foregroundColor, at: charIdx, effectiveRange: nil) as? NSColor ?? NSColor.black
                let rgb      = rawColor.usingColorSpace(.deviceRGB) ?? NSColor.black
                var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
                rgb.getRed(&r, green: &g, blue: &b, alpha: &a)

                // Try to expand from a single line to the full paragraph.
                // NSString.paragraphRange(for:) returns the range between hard
                // paragraph separators (\n, \r, U+2029). When a paragraph spans
                // multiple visual lines without an embedded newline, this captures
                // them all.  When each visual line ends with \n the range equals
                // the line (same result as selectionForLine — no regression).
                let nsStr     = attrStr.string as NSString
                let paraRange = nsStr.paragraphRange(for: NSRange(location: charIdx, length: 0))
                let lineSel   = page.selectionForLine(at: pagePoint)

                // Prefer paragraph selection but cap at 10 lines to avoid
                // accidentally selecting an entire column with no newlines.
                let useParagraph: Bool
                if let paraSel = page.selection(for: paraRange),
                   let paraStr = paraSel.string,
                   !paraStr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                   (paraSel.selectionsByLine().count) <= 10,
                   paraSel.selectionsByLine().count > 1 {
                    useParagraph = true
                    let selBounds = paraSel.bounds(for: page)
                    let viewRect  = pv.convert(selBounds, from: page)
                    let line = PDFTextLine(
                        text:     paraStr.trimmingCharacters(in: .whitespacesAndNewlines),
                        x:        selBounds.minX, y: selBounds.minY,
                        width:    selBounds.width, height: selBounds.height,
                        fontName: font.fontName,
                        fontSize: font.pointSize,
                        colorR:   Float(r), colorG: Float(g), colorB: Float(b)
                    )
                    parent.onTextLineTapped?(line, viewRect)
                    return nil
                } else {
                    useParagraph = false
                }

                // Single line fallback.
                guard !useParagraph,
                      let sel = lineSel,
                      let rawText = sel.string,
                      !rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                else { return event }

                let selBounds = sel.bounds(for: page)
                let viewRect  = pv.convert(selBounds, from: page)
                let line = PDFTextLine(
                    text:     rawText.trimmingCharacters(in: .whitespacesAndNewlines),
                    x:        selBounds.minX, y: selBounds.minY,
                    width:    selBounds.width, height: selBounds.height,
                    fontName: font.fontName,
                    fontSize: font.pointSize,
                    colorR:   Float(r), colorG: Float(g), colorB: Float(b)
                )
                parent.onTextLineTapped?(line, viewRect)
                return nil

            case .signature:
                if let page = pv.page(for: viewPoint, nearest: true) {
                    let pp = pv.convert(viewPoint, to: page)
                    pv.showSignaturePanel(at: viewPoint, pagePoint: pp, page: page, coordinator: self)
                    return nil
                }
                return event

            default:
                return event
            }
        }

        private func handleMouseDragged(event: NSEvent, pv: DrawablePDFView, viewPoint: CGPoint) -> NSEvent? {
            guard parent.activeTool == .shape,
                  let startPP = shapeDragStart,
                  let page    = shapeDragPage else { return event }
            let currentPP = pv.convert(viewPoint, to: page)
            let vm = parent.annotationViewModel

            if vm.shapeType == .line {
                // Native .line annotation: update startPoint/endPoint/bounds in-place.
                // The annotation layer invalidates synchronously — no ghost pixels.
                let dx = currentPP.x - startPP.x, dy = currentPP.y - startPP.y
                guard hypot(dx, dy) > 4 else { return nil }
                if let existing = shapePreviewAnn {
                    let pad = max(vm.shapeLineWidth, 8)
                    existing.startPoint = startPP
                    existing.endPoint   = currentPP
                    existing.bounds = CGRect(
                        x: min(startPP.x, currentPP.x) - pad,
                        y: min(startPP.y, currentPP.y) - pad,
                        width:  abs(currentPP.x - startPP.x) + pad * 2,
                        height: abs(currentPP.y - startPP.y) + pad * 2
                    )
                } else {
                    // First drag event: create the preview once and keep it.
                    if let old = shapePreviewAnn, let p = old.page { p.removeAnnotation(old) }
                    let preview = makeLineAnnotation(from: startPP, to: currentPP,
                                                     color: vm.shapeStrokeColor.withAlphaComponent(0.6),
                                                     lineWidth: vm.shapeLineWidth)
                    page.addAnnotation(preview)
                    shapePreviewAnn = preview
                }
            } else {
                // Rect / ellipse: remove old, add fresh preview each event.
                if let preview = shapePreviewAnn, let p = preview.page {
                    p.removeAnnotation(preview)
                }
                let rect = CGRect(
                    x: min(startPP.x, currentPP.x),
                    y: min(startPP.y, currentPP.y),
                    width:  abs(currentPP.x - startPP.x),
                    height: abs(currentPP.y - startPP.y)
                )
                guard rect.width > 4, rect.height > 4 else { shapePreviewAnn = nil; return nil }
                let subtype: PDFAnnotationSubtype = vm.shapeType == .rectangle ? .square : .circle
                let preview = PDFAnnotation(bounds: rect, forType: subtype, withProperties: nil)
                preview.color = vm.shapeStrokeColor.withAlphaComponent(0.6)
                let border = PDFBorder(); border.lineWidth = vm.shapeLineWidth; border.style = .solid
                preview.border = border
                page.addAnnotation(preview)
                shapePreviewAnn = preview
            }
            return nil
        }

        private func handleMouseUp(event: NSEvent, pv: DrawablePDFView, viewPoint: CGPoint) -> NSEvent? {
            guard parent.activeTool == .shape,
                  let startPP = shapeDragStart,
                  let page    = shapeDragPage else { return event }
            // Remove preview
            if let preview = shapePreviewAnn, let p = preview.page {
                p.removeAnnotation(preview)
                shapePreviewAnn = nil
            }
            let endPP = pv.convert(viewPoint, to: page)
            shapeDragStart = nil
            shapeDragPage  = nil

            let vm = parent.annotationViewModel
            if vm.shapeType == .line {
                let dx = endPP.x - startPP.x, dy = endPP.y - startPP.y
                guard hypot(dx, dy) > 8 else { return nil }
                let ann = makeLineAnnotation(from: startPP, to: endPP,
                                             color: vm.shapeStrokeColor,
                                             lineWidth: vm.shapeLineWidth)
                page.addAnnotation(ann)
                trackAnnotationAdd(ann, on: page)
                selectAnnotationForResize(ann)
                parent.onAnnotationAdded()
                parent.onPlacementDone?()
            } else {
                let rect = CGRect(
                    x: min(startPP.x, endPP.x),
                    y: min(startPP.y, endPP.y),
                    width:  abs(endPP.x - startPP.x),
                    height: abs(endPP.y - startPP.y)
                )
                guard rect.width > 8, rect.height > 8 else { return nil }
                let newShapeAnn = vm.addShape(type: vm.shapeType, rect: rect, on: page)
                trackAnnotationAdd(newShapeAnn, on: page)
                selectAnnotationForResize(newShapeAnn)
                parent.onAnnotationAdded()
                parent.onPlacementDone?()
            }
            return nil
        }

        func commitComment(text: String, at pagePoint: CGPoint, page: PDFPage,
                           existingAnnotation: PDFAnnotation?) {
            guard !text.isEmpty else { return }
            if let ann = existingAnnotation {
                ann.contents = text
            } else {
                let ann = PDFCommentAnnotation(at: pagePoint, text: text)
                page.addAnnotation(ann)
                trackAnnotationAdd(ann, on: page)
            }
            parent.onAnnotationAdded()
            parent.onPlacementDone?()
        }

        func commitSignature(name: String, fontName: String, color: NSColor,
                             fontSize: CGFloat, at pagePoint: CGPoint, page: PDFPage) {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }

            // Use a freeText annotation: PDFKit gives us native move + resize
            // handles when the user clicks it with the select tool.
            let pointSize = max(14, fontSize)
            let font = NSFont(name: fontName, size: pointSize)
                    ?? NSFont(name: "SnellRoundhand", size: pointSize)
                    ?? NSFont.systemFont(ofSize: pointSize)
            let textSize = (trimmed as NSString).size(withAttributes: [.font: font])
            let pad: CGFloat = 6
            let w = ceil(textSize.width)  + pad * 2
            let h = ceil(textSize.height) + pad * 2

            let bounds = CGRect(x: pagePoint.x - w / 2,
                                y: pagePoint.y - h / 2,
                                width: w, height: h)

            let ann = PDFAnnotation(bounds: bounds, forType: .freeText, withProperties: nil)
            ann.contents  = trimmed
            ann.font      = font
            ann.fontColor = color
            ann.color     = NSColor(white: 1, alpha: 0)   // fully transparent background
            let border = PDFBorder()
            border.lineWidth = 0                           // no border
            border.style = .solid
            ann.border    = border
            ann.isReadOnly = false
            ann.shouldDisplay = true
            ann.shouldPrint   = true
            ann.alignment = .center
            // Tag so double-click knows to open the signature editor
            ann.setValue("signature" as NSString,
                         forAnnotationKey: PDFAnnotationKey(rawValue: "/FolioType"))
            page.addAnnotation(ann)
            trackAnnotationAdd(ann, on: page)
            parent.onAnnotationAdded()
            parent.onPlacementDone?()
        }
    }
}

// MARK: - PDFImageAnnotation
// Stamp annotation that renders an NSImage.  Works as a standard PDFKit
// annotation: it is saved into the PDF, selectable, and resizable.

final class PDFImageAnnotation: PDFAnnotation {
    var image: NSImage

    init(image: NSImage, bounds: CGRect) {
        self.image = image
        super.init(bounds: bounds, forType: .stamp, withProperties: nil)
        color          = .clear
        shouldDisplay  = true
        shouldPrint    = true
        isReadOnly     = false
    }

    required init?(coder: NSCoder) { fatalError("NSCoder not supported") }

    override func draw(with box: PDFDisplayBox, in context: CGContext) {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
        context.draw(cgImage, in: bounds)
    }
}

// MARK: - PDFCommentAnnotation
// Stamp annotation that renders a minimal speech-bubble icon instead of the
// built-in PDFKit yellow dog-ear.  Uses .stamp so we have full drawing control.

final class PDFCommentAnnotation: PDFAnnotation {

    init(at point: CGPoint, text: String) {
        // 24 pt wide × 28 pt tall (body 23 pt + 5 pt tail)
        let w: CGFloat = 24, h: CGFloat = 28
        let bounds = CGRect(x: point.x - w / 2, y: point.y - 5, width: w, height: h)
        super.init(bounds: bounds, forType: .stamp, withProperties: nil)
        contents      = text
        color         = NSColor.systemBlue
        shouldDisplay = true
        shouldPrint   = true
        isReadOnly    = false
        // Tag so click detection and save logic can identify this annotation type.
        setValue("comment" as NSString,
                 forAnnotationKey: PDFAnnotationKey(rawValue: "/FolioType"))
    }

    required init?(coder: NSCoder) { fatalError("NSCoder not supported") }

    override func draw(with box: PDFDisplayBox, in context: CGContext) {
        let r = bounds
        let tail: CGFloat = 5          // height of the pointer triangle
        let cr:   CGFloat = 4          // corner radius
        // Body sits above the tail
        let body = CGRect(x: r.minX, y: r.minY + tail, width: r.width, height: r.height - tail)

        context.saveGState()
        // Subtle drop shadow
        context.setShadow(offset: CGSize(width: 0, height: -1.5), blur: 3,
                          color: NSColor.black.withAlphaComponent(0.22).cgColor)
        context.setFillColor(color.cgColor)

        // Build speech-bubble path: rounded rect + triangular tail at bottom-left
        let p = CGMutablePath()
        p.move(to:    CGPoint(x: body.minX + cr,              y: body.maxY))
        p.addLine(to: CGPoint(x: body.maxX - cr,              y: body.maxY))
        p.addQuadCurve(to:      CGPoint(x: body.maxX,         y: body.maxY - cr),
                       control: CGPoint(x: body.maxX,         y: body.maxY))
        p.addLine(to: CGPoint(x: body.maxX,                   y: body.minY + cr))
        p.addQuadCurve(to:      CGPoint(x: body.maxX - cr,    y: body.minY),
                       control: CGPoint(x: body.maxX,         y: body.minY))
        p.addLine(to: CGPoint(x: body.minX + cr * 2 + tail,   y: body.minY))
        p.addLine(to: CGPoint(x: body.minX + cr + tail * 0.4, y: r.minY))   // tail tip
        p.addLine(to: CGPoint(x: body.minX + cr,              y: body.minY))
        p.addQuadCurve(to:      CGPoint(x: body.minX,         y: body.minY + cr),
                       control: CGPoint(x: body.minX,         y: body.minY))
        p.addLine(to: CGPoint(x: body.minX,                   y: body.maxY - cr))
        p.addQuadCurve(to:      CGPoint(x: body.minX + cr,    y: body.maxY),
                       control: CGPoint(x: body.minX,         y: body.maxY))
        p.closeSubpath()

        context.addPath(p)
        context.fillPath()
        context.setShadow(offset: .zero, blur: 0)

        // Two white horizontal lines suggesting text content
        context.setStrokeColor(NSColor.white.withAlphaComponent(0.88).cgColor)
        context.setLineWidth(1.5)
        context.setLineCap(.round)
        let midY = body.midY
        let lx = body.minX + 4, rx = body.maxX - 4
        context.strokeLineSegments(between: [
            CGPoint(x: lx, y: midY + 3), CGPoint(x: rx,     y: midY + 3),
            CGPoint(x: lx, y: midY - 3), CGPoint(x: rx - 3, y: midY - 3)
        ])

        context.restoreGState()
    }
}

// MARK: - PDFTextStampAnnotation
// Renders a text-label stamp (e.g. "APPROVED", "DRAFT") with a coloured border
// and bold condensed text, similar to a rubber-stamp look.

final class PDFTextStampAnnotation: PDFAnnotation {
    let label: String
    let stampColor: NSColor

    init(label: String, color: NSColor, bounds: CGRect) {
        self.label      = label
        self.stampColor = color
        super.init(bounds: bounds, forType: .stamp, withProperties: nil)
        self.color     = color
        shouldDisplay  = true
        shouldPrint    = true
        isReadOnly     = false
        setValue("textstamp" as NSString,
                 forAnnotationKey: PDFAnnotationKey(rawValue: "/FolioType"))
    }

    required init?(coder: NSCoder) { fatalError("NSCoder not supported") }

    override func draw(with box: PDFDisplayBox, in context: CGContext) {
        let r = bounds
        let inset: CGFloat = 2.5
        let inner = r.insetBy(dx: inset, dy: inset)
        let cr: CGFloat = 4

        context.saveGState()

        // Fill with very faint tint
        context.setFillColor(stampColor.withAlphaComponent(0.07).cgColor)
        let fillPath = CGPath(roundedRect: inner, cornerWidth: cr, cornerHeight: cr, transform: nil)
        context.addPath(fillPath)
        context.fillPath()

        // Double-line border (outer slightly lighter, inner full colour)
        let outerPath = CGPath(roundedRect: inner, cornerWidth: cr, cornerHeight: cr, transform: nil)
        context.addPath(outerPath)
        context.setStrokeColor(stampColor.withAlphaComponent(0.4).cgColor)
        context.setLineWidth(3.5)
        context.strokePath()

        let innerInset = inner.insetBy(dx: 2.5, dy: 2.5)
        let innerPath = CGPath(roundedRect: innerInset, cornerWidth: cr - 1, cornerHeight: cr - 1, transform: nil)
        context.addPath(innerPath)
        context.setStrokeColor(stampColor.cgColor)
        context.setLineWidth(1.5)
        context.strokePath()

        // Label text — bold, condensed, centred
        let fontSize = min(inner.height * 0.52, 18)
        let font = CTFontCreateWithName("HelveticaNeue-CondensedBold" as CFString, fontSize, nil)
        let attrs: [CFString: Any] = [
            kCTFontAttributeName:            font,
            kCTForegroundColorAttributeName: stampColor.cgColor
        ]
        let attrStr = CFAttributedStringCreate(nil, label as CFString, attrs as CFDictionary)!
        let line    = CTLineCreateWithAttributedString(attrStr)
        let lineBounds = CTLineGetBoundsWithOptions(line, [])
        let tx = inner.midX - lineBounds.width / 2
        let ty = inner.midY - lineBounds.height / 2 - lineBounds.origin.y
        context.textMatrix = CGAffineTransform(scaleX: 1, y: 1)
        context.textPosition = CGPoint(x: tx, y: ty)
        CTLineDraw(line, context)

        context.restoreGState()
    }
}

// MARK: - Line annotation factory
// Uses the native PDFKit .line type so PDFKit renders it in the annotation
// layer (synchronous invalidation) rather than the CATiledLayer page cache.
// This eliminates ghost pixels when the annotation is moved or dragged.
private func makeLineAnnotation(from start: CGPoint, to end: CGPoint,
                                 color: NSColor, lineWidth: CGFloat) -> PDFAnnotation {
    let pad = max(lineWidth, 8)
    let bounds = CGRect(
        x: min(start.x, end.x) - pad,
        y: min(start.y, end.y) - pad,
        width:  abs(end.x - start.x) + pad * 2,
        height: abs(end.y - start.y) + pad * 2
    )
    let ann = PDFAnnotation(bounds: bounds, forType: .line, withProperties: nil)
    // startPoint / endPoint are in page coordinate space.
    ann.startPoint = start
    ann.endPoint   = end
    ann.color      = color
    let border = PDFBorder()
    border.lineWidth = lineWidth
    border.style     = .solid
    ann.border = border
    return ann
}


fileprivate final class DrawablePDFView: PDFView {

    weak var coordinator: PDFKitView.Coordinator?

    // MARK: Sticky popover state
    private var stickyPopover: NSPopover?
    private var pendingPage: PDFPage?
    private var pendingPagePoint: CGPoint = .zero

    override var acceptsFirstResponder: Bool { true }

    // MARK: Cursor
    override func resetCursorRects() {
        super.resetCursorRects()
    }

    // MARK: Inline sticky popover for comments

    func showStickyPopover(at viewPoint: CGPoint, coordinator: PDFKitView.Coordinator,
                           existingAnnotation: PDFAnnotation?, viewOnly: Bool) {
        stickyPopover?.close()
        stickyPopover = nil

        guard let page = self.page(for: viewPoint, nearest: true) else { return }
        pendingPage      = page
        pendingPagePoint = self.convert(viewPoint, to: page)

        let popover = NSPopover()
        popover.behavior = .semitransient
        popover.animates = true

        let vc = StickyNoteViewController()
        vc.prefillText   = existingAnnotation?.contents ?? ""
        vc.isEditing     = existingAnnotation != nil
        vc.viewOnly      = viewOnly
        vc.onCommit = { [weak self, weak coordinator, weak popover] text in
            popover?.close()
            guard let self, let coordinator else { return }
            coordinator.commitComment(text: text,
                                      at: self.pendingPagePoint,
                                      page: self.pendingPage!,
                                      existingAnnotation: existingAnnotation)
            self.stickyPopover = nil
        }
        vc.onCancel = { [weak popover, weak self] in
            popover?.close()
            self?.stickyPopover = nil
        }
        popover.contentViewController = vc
        stickyPopover = popover

        let anchor = NSRect(x: viewPoint.x, y: viewPoint.y, width: 1, height: 1)
        popover.show(relativeTo: anchor, of: self, preferredEdge: .minY)
    }

    // MARK: Signature panel

    private var signaturePopover: NSPopover?
    private var sigPage: PDFPage?
    private var sigPagePoint: CGPoint = .zero

    func showSignaturePanel(at viewPoint: CGPoint, pagePoint: CGPoint,
                            page: PDFPage, coordinator: PDFKitView.Coordinator) {
        signaturePopover?.close()
        signaturePopover = nil
        sigPage      = page
        sigPagePoint = pagePoint

        let popover  = NSPopover()
        popover.behavior = .semitransient
        popover.animates = true

        let vc = SignaturePanelViewController()
        vc.onCommit = { [weak self, weak coordinator, weak popover] name, fontName, color, fontSize in
            popover?.close()
            guard let self, let coordinator,
                  let page = self.sigPage else { return }
            coordinator.commitSignature(name: name, fontName: fontName, color: color,
                                        fontSize: fontSize, at: self.sigPagePoint, page: page)
            self.signaturePopover = nil
        }
        vc.onCancel = { [weak popover, weak self] in
            popover?.close()
            self?.signaturePopover = nil
        }
        popover.contentViewController = vc
        signaturePopover = popover

        let anchor = NSRect(x: viewPoint.x, y: viewPoint.y, width: 1, height: 1)
        popover.show(relativeTo: anchor, of: self, preferredEdge: .minY)
    }

    // MARK: - Signature resize popover

    private var sigResizePopover: NSPopover?

    func showSignatureResizePopover(at viewPoint: CGPoint, annotation: PDFAnnotation) {
        sigResizePopover?.close()
        sigResizePopover = nil
        let popover = NSPopover()
        popover.behavior = .semitransient
        popover.animates = true
        let vc = SignatureResizeViewController(annotation: annotation, pdfView: self)
        vc.onDismiss = { [weak popover, weak self] in
            popover?.close()
            self?.sigResizePopover = nil
        }
        popover.contentViewController = vc
        sigResizePopover = popover
        let anchor = NSRect(x: viewPoint.x, y: viewPoint.y, width: 1, height: 1)
        popover.show(relativeTo: anchor, of: self, preferredEdge: .minY)
    }

    // MARK: - Text box edit popover

    private var textBoxEditPopover: NSPopover?

    func showTextBoxEditPopover(at viewPoint: CGPoint, annotation: PDFAnnotation) {
        textBoxEditPopover?.close()
        let popover = NSPopover()
        popover.behavior = .semitransient
        popover.animates = true
        let vc = TextBoxEditViewController()
        vc.currentText = annotation.contents ?? ""
        vc.currentFont = annotation.font ?? .systemFont(ofSize: 14)
        vc.currentColor = annotation.fontColor ?? .black
        vc.onCommit = { [weak popover, weak self] text, font, color in
            annotation.contents  = text
            annotation.font      = font
            annotation.fontColor = color
            popover?.close()
            self?.textBoxEditPopover = nil
        }
        vc.onCancel = { [weak popover, weak self] in
            popover?.close()
            self?.textBoxEditPopover = nil
        }
        popover.contentViewController = vc
        textBoxEditPopover = popover
        let anchor = NSRect(x: viewPoint.x, y: viewPoint.y, width: 1, height: 1)
        popover.show(relativeTo: anchor, of: self, preferredEdge: .minY)
    }

    // MARK: - Signature edit popover (pre-fills existing text)

    func showSignatureEditPopover(at viewPoint: CGPoint, annotation: PDFAnnotation,
                                   pagePoint: CGPoint, page: PDFPage,
                                   coordinator: PDFKitView.Coordinator) {
        signaturePopover?.close()
        signaturePopover = nil
        sigPage      = page
        sigPagePoint = pagePoint
        let popover  = NSPopover()
        popover.behavior = .semitransient
        popover.animates = true
        let vc = SignaturePanelViewController()
        vc.prefillName = annotation.contents ?? ""
        vc.onCommit = { [weak self, weak popover, weak annotation] name, fontName, color, fontSize in
            popover?.close()
            guard let ann = annotation else { return }
            let pointSize = max(14, fontSize)
            let font = NSFont(name: fontName, size: pointSize)
                ?? NSFont.systemFont(ofSize: pointSize)
            ann.contents  = name
            ann.font      = font
            ann.fontColor = color
            self?.signaturePopover = nil
        }
        vc.onCancel = { [weak popover, weak self] in
            popover?.close()
            self?.signaturePopover = nil
        }
        popover.contentViewController = vc
        signaturePopover = popover
        let anchor = NSRect(x: viewPoint.x, y: viewPoint.y, width: 1, height: 1)
        popover.show(relativeTo: anchor, of: self, preferredEdge: .minY)
    }

    // MARK: - Image drop from Finder

    var onImageDropped: ((NSImage, PDFPage, CGRect) -> Void)?

    func enableImageDrop(handler: ((NSImage, PDFPage, CGRect) -> Void)?) {
        onImageDropped = handler
        registerForDraggedTypes([.fileURL, .tiff,
                                 NSPasteboard.PasteboardType("public.image"),
                                 NSPasteboard.PasteboardType("public.png"),
                                 NSPasteboard.PasteboardType("public.jpeg")])
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard imageFromPasteboard(sender.draggingPasteboard) != nil else {
            return super.draggingEntered(sender)
        }
        return .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard imageFromPasteboard(sender.draggingPasteboard) != nil else {
            return super.draggingUpdated(sender)
        }
        return .copy
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let dropPoint = convert(sender.draggingLocation, from: nil)
        guard let image = imageFromPasteboard(sender.draggingPasteboard),
              let page  = self.page(for: dropPoint, nearest: true) else { return false }
        let pagePoint = convert(dropPoint, to: page)
        let w: CGFloat = 200
        let h = image.size.width > 0 ? w * image.size.height / image.size.width : 200
        // Rect in PDF coords (origin bottom-left), centred on drop point.
        let pdfRect = CGRect(x: pagePoint.x - w / 2, y: pagePoint.y - h / 2,
                             width: w, height: h)
        // Create PDFImageAnnotation directly via coordinator so it is immediately
        // selectable and resizable without any MuPDF round-trip.
        coordinator?.dropImage(image, on: page, at: pdfRect)
        return true
    }

    private func imageFromPasteboard(_ pb: NSPasteboard) -> NSImage? {
        let opts: [NSPasteboard.ReadingOptionKey: Any] = [
            .urlReadingFileURLsOnly: true,
            .urlReadingContentsConformToTypes: ["public.image"]
        ]
        if let urls = pb.readObjects(forClasses: [NSURL.self], options: opts) as? [URL],
           let url = urls.first {
            return NSImage(contentsOf: url)
        }
        if let data = pb.data(forType: .tiff) { return NSImage(data: data) }
        return nil
    }
}

// MARK: - StickyNoteViewController
// Clean yellow sticky note in a popover. Supports new comments and editing existing ones.

private final class StickyNoteViewController: NSViewController, NSTextViewDelegate {

    var onCommit: ((String) -> Void)?
    var onCancel: (() -> Void)?
    var prefillText: String = ""
    var isEditing: Bool = false
    var viewOnly: Bool = false           // when true: read-only with Edit button

    private let textView = NSTextView()
    private let placeholder = NSTextField(labelWithString: "Write your comment…")
    private var actionButton: NSButton!
    private var titleField:   NSTextField!

    override func loadView() {
        let W: CGFloat = 260, H: CGFloat = 170
        let container = NSView(frame: NSRect(x: 0, y: 0, width: W, height: H))
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor(red: 1.0, green: 0.96, blue: 0.60, alpha: 1).cgColor
        container.layer?.cornerRadius = 6

        // ── Header ────────────────────────────────────────────────────
        let header = NSView(frame: NSRect(x: 0, y: H - 32, width: W, height: 32))
        header.wantsLayer = true
        header.layer?.backgroundColor = NSColor(red: 0.98, green: 0.88, blue: 0.30, alpha: 1).cgColor

        let icon = NSImageView(frame: NSRect(x: 10, y: 7, width: 16, height: 16))
        icon.image = NSImage(systemSymbolName: "note.text", accessibilityDescription: nil)
        icon.contentTintColor = .black.withAlphaComponent(0.6)
        header.addSubview(icon)

        let title = NSTextField(labelWithString: viewOnly ? "Comment" : (isEditing ? "Edit Comment" : "New Comment"))
        title.frame = NSRect(x: 32, y: 8, width: 150, height: 16)
        title.font = .systemFont(ofSize: 12, weight: .semibold)
        title.textColor = .black.withAlphaComponent(0.75)
        header.addSubview(title)
        titleField = title

        let buttonTitle: String = viewOnly ? "Edit" : (isEditing ? "Save" : "Add")
        let addBtn = NSButton(title: buttonTitle,
                             target: self,
                             action: viewOnly ? #selector(enterEditMode) : #selector(commit))
        addBtn.frame = NSRect(x: W - 50, y: 6, width: 44, height: 20)
        addBtn.bezelStyle = .inline
        addBtn.font = .systemFont(ofSize: 11, weight: .medium)
        header.addSubview(addBtn)
        actionButton = addBtn
        container.addSubview(header)

        // ── Text area (white card inside yellow sticky) ────────────────
        let card = NSView(frame: NSRect(x: 8, y: 8, width: W - 16, height: H - 48))
        card.wantsLayer = true
        card.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.55).cgColor
        card.layer?.cornerRadius = 4
        container.addSubview(card)

        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: card.frame.width,
                                               height: card.frame.height))
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.borderType = .noBorder
        scroll.autohidesScrollers = true

        textView.frame = NSRect(x: 0, y: 0, width: card.frame.width, height: card.frame.height)
        textView.minSize = NSSize(width: 0, height: card.frame.height)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude,
                                   height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.containerSize = NSSize(width: card.frame.width, height: .greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        textView.isRichText = false
        textView.font = .systemFont(ofSize: 13)
        textView.backgroundColor = .clear
        textView.drawsBackground = false
        textView.isEditable = !viewOnly
        textView.isSelectable = true
        textView.textContainerInset = NSSize(width: 6, height: 6)
        textView.delegate = self
        if !prefillText.isEmpty { textView.string = prefillText }
        scroll.documentView = textView
        card.addSubview(scroll)

        // Placeholder label (hidden once there's text)
        placeholder.frame = NSRect(x: 12, y: card.frame.height - 26, width: card.frame.width - 16, height: 20)
        placeholder.font = .systemFont(ofSize: 13)
        placeholder.textColor = .placeholderTextColor
        placeholder.isHidden = !prefillText.isEmpty
        card.addSubview(placeholder)

        self.view = container
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        // In view-only mode, don't grab first responder — just display.
        guard !viewOnly else { return }
        // Deferred so the popover window is fully ready before we steal focus
        DispatchQueue.main.async {
            self.view.window?.makeFirstResponder(self.textView)
            // Place cursor at end of any pre-filled text
            let len = self.textView.string.count
            self.textView.setSelectedRange(NSRange(location: len, length: 0))
        }
    }

    @objc private func enterEditMode() {
        viewOnly = false
        textView.isEditable = true
        titleField.stringValue = "Edit Comment"
        actionButton.title  = "Save"
        actionButton.target = self
        actionButton.action = #selector(commit)
        DispatchQueue.main.async {
            self.view.window?.makeFirstResponder(self.textView)
            let len = self.textView.string.count
            self.textView.setSelectedRange(NSRange(location: len, length: 0))
        }
    }

    // Hide placeholder as soon as user types
    func textDidChange(_ notification: Notification) {
        placeholder.isHidden = !textView.string.isEmpty
    }

    @objc private func commit() {
        onCommit?(textView.string.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    override func cancelOperation(_ sender: Any?) { onCancel?() }
}

// MARK: - TextBoxEditViewController
// Simple popover to edit the text content, font size, and color of a freeText annotation.

private final class TextBoxEditViewController: NSViewController {

    var currentText: String  = ""
    var currentFont: NSFont  = .systemFont(ofSize: 14)
    var currentColor: NSColor = .black
    var onCommit: ((String, NSFont, NSColor) -> Void)?
    var onCancel: (() -> Void)?

    private let textView   = NSTextView()
    private let colorWell  = NSColorWell()
    private let sizeSlider = NSSlider()
    private let sizeLabel  = NSTextField(labelWithString: "")

    override func loadView() {
        let W: CGFloat = 300, H: CGFloat = 200
        let container = NSView(frame: NSRect(x: 0, y: 0, width: W, height: H))
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        container.layer?.cornerRadius = 6

        // Header
        let header = NSView(frame: NSRect(x: 0, y: H - 36, width: W, height: 36))
        header.wantsLayer = true
        header.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        let title = NSTextField(labelWithString: "Edit Text")
        title.frame = NSRect(x: 12, y: 10, width: 120, height: 16)
        title.font  = .systemFont(ofSize: 12, weight: .semibold)
        header.addSubview(title)
        let cancelBtn = NSButton(title: "Cancel", target: self, action: #selector(didCancel))
        cancelBtn.frame = NSRect(x: W - 116, y: 8, width: 56, height: 20)
        cancelBtn.bezelStyle = .inline
        header.addSubview(cancelBtn)
        let doneBtn = NSButton(title: "Save", target: self, action: #selector(didCommit))
        doneBtn.frame = NSRect(x: W - 56, y: 8, width: 44, height: 20)
        doneBtn.bezelStyle = .inline
        header.addSubview(doneBtn)
        container.addSubview(header)

        // Size + color row
        let sizeTitle = NSTextField(labelWithString: "Size")
        sizeTitle.frame = NSRect(x: 12, y: H - 56, width: 30, height: 14)
        sizeTitle.font  = .systemFont(ofSize: 10)
        sizeTitle.textColor = .secondaryLabelColor
        container.addSubview(sizeTitle)

        sizeLabel.frame = NSRect(x: 44, y: H - 56, width: 36, height: 14)
        sizeLabel.font  = .systemFont(ofSize: 10)
        sizeLabel.textColor = .secondaryLabelColor
        container.addSubview(sizeLabel)

        sizeSlider.frame    = NSRect(x: 84, y: H - 58, width: W - 148, height: 18)
        sizeSlider.minValue = 8
        sizeSlider.maxValue = 72
        sizeSlider.doubleValue = Double(currentFont.pointSize)
        sizeSlider.target   = self
        sizeSlider.action   = #selector(sizeChanged)
        container.addSubview(sizeSlider)

        colorWell.frame  = NSRect(x: W - 52, y: H - 60, width: 40, height: 22)
        colorWell.color  = currentColor
        container.addSubview(colorWell)

        // Text view
        let scroll = NSScrollView(frame: NSRect(x: 12, y: 12, width: W - 24, height: H - 76))
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers  = true
        scroll.borderType          = .bezelBorder

        textView.frame = NSRect(origin: .zero, size: CGSize(width: W - 24, height: max(H - 76, 200)))
        textView.isEditable         = true
        textView.isSelectable       = true
        textView.isRichText         = false
        textView.font               = currentFont
        textView.textColor          = currentColor
        textView.string             = currentText
        textView.drawsBackground    = true
        textView.backgroundColor    = .white
        scroll.documentView = textView
        container.addSubview(scroll)

        self.view = container
        updateSizeLabel()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        DispatchQueue.main.async { self.view.window?.makeFirstResponder(self.textView) }
    }

    @objc private func sizeChanged() {
        updateSizeLabel()
        let size = CGFloat(sizeSlider.doubleValue)
        let newFont = NSFont(name: currentFont.fontName, size: size) ?? NSFont.systemFont(ofSize: size)
        currentFont = newFont
        textView.font = newFont
    }

    private func updateSizeLabel() {
        sizeLabel.stringValue = "\(Int(sizeSlider.doubleValue))pt"
    }

    @objc private func didCommit() {
        let size = CGFloat(sizeSlider.doubleValue)
        let font = NSFont(name: currentFont.fontName, size: size) ?? NSFont.systemFont(ofSize: size)
        onCommit?(textView.string, font, colorWell.color)
    }

    @objc private func didCancel() { onCancel?() }
    override func cancelOperation(_ sender: Any?) { onCancel?() }
}

// MARK: - SignaturePanelViewController
// Popover with a drawing canvas for capturing a handwritten signature.

private final class SignaturePanelViewController: NSViewController {

    var onCommit: ((String, String, NSColor, CGFloat) -> Void)?  // name, fontName, color, fontSize
    var onCancel: (() -> Void)?
    /// Pre-fill with existing signature text when editing.
    var prefillName: String = ""

    private let nameField  = NSTextField()
    private let fontPopup  = NSPopUpButton()
    private let colorWell  = NSColorWell()
    private let preview    = NSTextField(labelWithString: "")
    private let sizeSlider = NSSlider()
    private let sizeLabel  = NSTextField(labelWithString: "28 pt")

    // Curated handwriting / script fonts available on macOS.
    private let signatureFonts: [(label: String, fontName: String)] = [
        ("Snell Roundhand",   "SnellRoundhand"),
        ("Snell Bold",        "SnellRoundhand-Bold"),
        ("Apple Chancery",    "Apple-Chancery"),
        ("Zapfino",           "Zapfino"),
        ("Brush Script MT",   "BrushScriptMT"),
        ("Bradley Hand",      "BradleyHandITCTT-Bold"),
        ("Noteworthy",        "Noteworthy-Light"),
        ("Marker Felt",       "MarkerFelt-Thin")
    ]

    override func loadView() {
        let W: CGFloat = 360, H: CGFloat = 290
        let container = NSView(frame: NSRect(x: 0, y: 0, width: W, height: H))
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        container.layer?.cornerRadius = 6

        // Header
        let header = NSView(frame: NSRect(x: 0, y: H - 36, width: W, height: 36))
        header.wantsLayer = true
        header.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor

        let title = NSTextField(labelWithString: "Signature")
        title.frame = NSRect(x: 12, y: 10, width: 180, height: 16)
        title.font  = .systemFont(ofSize: 12, weight: .semibold)
        header.addSubview(title)

        let cancelBtn = NSButton(title: "Cancel", target: self, action: #selector(cancel))
        cancelBtn.frame = NSRect(x: W - 116, y: 8, width: 56, height: 20)
        cancelBtn.bezelStyle = .inline
        cancelBtn.font = .systemFont(ofSize: 11)
        header.addSubview(cancelBtn)

        let doneBtn = NSButton(title: "Add", target: self, action: #selector(commit))
        doneBtn.frame = NSRect(x: W - 56, y: 8, width: 44, height: 20)
        doneBtn.bezelStyle = .inline
        doneBtn.font = .systemFont(ofSize: 11, weight: .medium)
        header.addSubview(doneBtn)
        container.addSubview(header)

        // Name field
        let nameLabel = NSTextField(labelWithString: "Name")
        nameLabel.frame = NSRect(x: 12, y: H - 64, width: 60, height: 16)
        nameLabel.font  = .systemFont(ofSize: 11)
        nameLabel.textColor = .secondaryLabelColor
        container.addSubview(nameLabel)

        nameField.frame = NSRect(x: 12, y: H - 88, width: W - 24, height: 26)
        nameField.placeholderString = "Your name"
        nameField.font = .systemFont(ofSize: 13)
        nameField.isBezeled = true
        nameField.bezelStyle = .roundedBezel
        nameField.focusRingType = .default
        nameField.drawsBackground = true
        nameField.backgroundColor = .textBackgroundColor
        nameField.target = self
        nameField.action = #selector(updatePreview)
        nameField.delegate = self
        container.addSubview(nameField)

        // Font picker + color well
        fontPopup.frame = NSRect(x: 12, y: H - 120, width: W - 80, height: 24)
        for entry in signatureFonts { fontPopup.addItem(withTitle: entry.label) }
        fontPopup.target = self
        fontPopup.action = #selector(updatePreview)
        container.addSubview(fontPopup)

        colorWell.frame = NSRect(x: W - 60, y: H - 120, width: 48, height: 24)
        colorWell.color = NSColor(calibratedRed: 0.16, green: 0.20, blue: 0.55, alpha: 1) // ink blue
        colorWell.target = self
        colorWell.action = #selector(updatePreview)
        container.addSubview(colorWell)

        // Size slider
        let sizeTitleLabel = NSTextField(labelWithString: "Size")
        sizeTitleLabel.frame = NSRect(x: 12, y: H - 144, width: 40, height: 16)
        sizeTitleLabel.font  = .systemFont(ofSize: 11)
        sizeTitleLabel.textColor = .secondaryLabelColor
        container.addSubview(sizeTitleLabel)

        sizeLabel.frame = NSRect(x: W - 52, y: H - 144, width: 40, height: 16)
        sizeLabel.font  = .systemFont(ofSize: 11)
        sizeLabel.textColor = .secondaryLabelColor
        sizeLabel.alignment = .right
        container.addSubview(sizeLabel)

        sizeSlider.frame    = NSRect(x: 56, y: H - 168, width: W - 112, height: 22)
        sizeSlider.minValue = 14
        sizeSlider.maxValue = 72
        sizeSlider.intValue = 28
        sizeSlider.target   = self
        sizeSlider.action   = #selector(updatePreview)
        container.addSubview(sizeSlider)

        // Preview area
        let previewBG = NSView(frame: NSRect(x: 12, y: 12, width: W - 24, height: H - 188))
        previewBG.wantsLayer = true
        previewBG.layer?.backgroundColor = NSColor.white.cgColor
        previewBG.layer?.cornerRadius = 4
        previewBG.layer?.borderColor = NSColor.separatorColor.cgColor
        previewBG.layer?.borderWidth = 1
        container.addSubview(previewBG)

        preview.frame = previewBG.bounds.insetBy(dx: 8, dy: 4)
        preview.alignment = .center
        preview.isBezeled = false
        preview.drawsBackground = false
        preview.isEditable = false
        preview.lineBreakMode = .byTruncatingTail
        previewBG.addSubview(preview)

        self.view = container
        if !prefillName.isEmpty {
            nameField.stringValue = prefillName
        }
        updatePreview()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        DispatchQueue.main.async { self.view.window?.makeFirstResponder(self.nameField) }
    }

    @objc private func updatePreview() {
        let name = nameField.stringValue.isEmpty ? "Your Name" : nameField.stringValue
        let entry = signatureFonts[fontPopup.indexOfSelectedItem]
        let size  = CGFloat(sizeSlider.integerValue)
        sizeLabel.stringValue = "\(sizeSlider.integerValue) pt"
        let font  = NSFont(name: entry.fontName, size: size) ?? .systemFont(ofSize: size)
        preview.attributedStringValue = NSAttributedString(
            string: name,
            attributes: [
                .font: font,
                .foregroundColor: nameField.stringValue.isEmpty
                    ? NSColor.tertiaryLabelColor
                    : colorWell.color
            ])
    }

    @objc private func commit() {
        let name = nameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { onCancel?(); return }
        let entry = signatureFonts[fontPopup.indexOfSelectedItem]
        onCommit?(name, entry.fontName, colorWell.color, CGFloat(sizeSlider.integerValue))
    }

    @objc private func cancel() { onCancel?() }
    override func cancelOperation(_ sender: Any?) { onCancel?() }
}

extension SignaturePanelViewController: NSTextFieldDelegate {
    func controlTextDidChange(_ obj: Notification) { updatePreview() }
}

// MARK: - SignatureResizeViewController
// Popover shown when the user clicks an existing signature (freeText) annotation.
// Lets them adjust font size and ink colour without deleting and re-placing.

private final class SignatureResizeViewController: NSViewController {

    private let annotation: PDFAnnotation
    private weak var pdfView: PDFView?
    var onDismiss: (() -> Void)?

    private let sizeSlider = NSSlider()
    private let sizeLabel  = NSTextField(labelWithString: "")
    private let colorWell  = NSColorWell()

    init(annotation: PDFAnnotation, pdfView: PDFView) {
        self.annotation = annotation
        self.pdfView    = pdfView
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        let W: CGFloat = 300, H: CGFloat = 110
        let container = NSView(frame: NSRect(x: 0, y: 0, width: W, height: H))
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        container.layer?.cornerRadius = 6

        // ── Header ─────────────────────────────────────────────────────
        let header = NSView(frame: NSRect(x: 0, y: H - 34, width: W, height: 34))
        header.wantsLayer = true
        header.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        let title = NSTextField(labelWithString: "Adjust Signature")
        title.frame = NSRect(x: 12, y: 10, width: 160, height: 14)
        title.font  = .systemFont(ofSize: 12, weight: .semibold)
        header.addSubview(title)
        let doneBtn = NSButton(title: "Done", target: self, action: #selector(done))
        doneBtn.frame = NSRect(x: W - 52, y: 7, width: 40, height: 20)
        doneBtn.bezelStyle = .inline
        doneBtn.font = .systemFont(ofSize: 11, weight: .medium)
        header.addSubview(doneBtn)
        container.addSubview(header)

        let currentSize = annotation.font?.pointSize ?? 28

        // ── Size row ────────────────────────────────────────────────────
        let szLbl = NSTextField(labelWithString: "Size")
        szLbl.frame = NSRect(x: 12, y: H - 62, width: 32, height: 16)
        szLbl.font  = .systemFont(ofSize: 11)
        szLbl.textColor = .secondaryLabelColor
        container.addSubview(szLbl)

        sizeLabel.frame     = NSRect(x: W - 48, y: H - 62, width: 36, height: 16)
        sizeLabel.font      = .systemFont(ofSize: 11)
        sizeLabel.alignment = .right
        sizeLabel.textColor = .secondaryLabelColor
        sizeLabel.stringValue = "\(Int(currentSize)) pt"
        container.addSubview(sizeLabel)

        sizeSlider.frame    = NSRect(x: 50, y: H - 68, width: W - 106, height: 22)
        sizeSlider.minValue = 10
        sizeSlider.maxValue = 96
        sizeSlider.doubleValue = Double(currentSize)
        sizeSlider.target   = self
        sizeSlider.action   = #selector(applyChange)
        container.addSubview(sizeSlider)

        // ── Color row ───────────────────────────────────────────────────
        let clrLbl = NSTextField(labelWithString: "Color")
        clrLbl.frame = NSRect(x: 12, y: H - 94, width: 36, height: 16)
        clrLbl.font  = .systemFont(ofSize: 11)
        clrLbl.textColor = .secondaryLabelColor
        container.addSubview(clrLbl)

        colorWell.frame  = NSRect(x: 52, y: H - 100, width: 28, height: 22)
        colorWell.color  = annotation.fontColor
            ?? NSColor(calibratedRed: 0.16, green: 0.20, blue: 0.55, alpha: 1)
        colorWell.target = self
        colorWell.action = #selector(applyChange)
        container.addSubview(colorWell)

        self.view = container
    }

    @objc private func applyChange() {
        let size = CGFloat(sizeSlider.doubleValue)
        sizeLabel.stringValue = "\(Int(size)) pt"
        guard let currentFont = annotation.font else { return }
        let newFont = NSFont(name: currentFont.fontName, size: size)
            ?? NSFont.systemFont(ofSize: size)
        let text    = annotation.contents ?? ""
        let pad: CGFloat = 6
        let textSize = (text as NSString).size(withAttributes: [.font: newFont])
        let cx = annotation.bounds.midX
        let cy = annotation.bounds.midY
        annotation.font      = newFont
        annotation.fontColor = colorWell.color
        annotation.bounds    = CGRect(
            x: cx - (ceil(textSize.width)  + pad * 2) / 2,
            y: cy - (ceil(textSize.height) + pad * 2) / 2,
            width:  ceil(textSize.width)  + pad * 2,
            height: ceil(textSize.height) + pad * 2
        )
        if let pv = pdfView { pv.setNeedsDisplay(pv.bounds) }
    }

    @objc private func done() { onDismiss?() }
    override func cancelOperation(_ sender: Any?) { onDismiss?() }
}

