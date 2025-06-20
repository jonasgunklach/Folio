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
        let pdfView = DrawablePDFView()
        pdfView.coordinator = context.coordinator
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
        context.coordinator.installCursorMonitor(for: pdfView as! DrawablePDFView)
        context.coordinator.installCommentAndSignatureMonitor(for: pdfView as! DrawablePDFView)

        applyReadingMode(readingMode, to: pdfView)
        return pdfView
    }

    func updateNSView(_ pdfView: PDFView, context: Context) {
        // Keep coordinator in sync with the latest struct values
        context.coordinator.parent = self
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
                guard tool == .highlight || tool == .underline || tool == .strikethrough else {
                    return event
                }
                let viewPoint = pv.convert(event.locationInWindow, from: nil)
                guard pv.bounds.contains(viewPoint) else { return event }
                DispatchQueue.main.async { NSCursor.iBeam.set() }
                return event
            }
        }

        private func applyAnnotationIfNeeded() {
            guard let pdfView = monitoredPDFView,
                  let selection = pdfView.currentSelection,
                  !(selection.string ?? "").isEmpty else { return }

            let tool = parent.activeTool
            guard tool == .highlight || tool == .underline || tool == .strikethrough else { return }

            // Iterate per-line selections so each annotation covers exactly one line of text
            let lineSelections = selection.selectionsByLine() ?? [selection]
            for lineSel in lineSelections {
                for page in lineSel.pages {
                    let bounds = lineSel.bounds(for: page)
                    guard !bounds.isEmpty else { continue }
                    let type: PDFAnnotationSubtype
                    switch tool {
                    case .highlight:     type = .highlight
                    case .underline:     type = .underline
                    case .strikethrough: type = .strikeOut
                    default: continue
                    }
                    let ann = PDFAnnotation(bounds: bounds, forType: type, withProperties: nil)
                    switch tool {
                    case .highlight:
                        ann.color = parent.highlightColor.withAlphaComponent(parent.annotationOpacity)
                    case .underline:
                        ann.color = parent.underlineColor
                    case .strikethrough:
                        ann.color = parent.strikethroughColor
                    default: break
                    }
                    page.addAnnotation(ann)
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

        // MARK: Comment + Signature — unified event monitor

        private var commentSigMonitor: Any?
        private weak var commentSigPDFView: DrawablePDFView?

        fileprivate func installCommentAndSignatureMonitor(for pdfView: DrawablePDFView) {
            commentSigPDFView = pdfView
            commentSigMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
                guard let self, let pv = self.commentSigPDFView else { return event }
                // Ignore clicks that aren't in the PDFView's own window
                // (e.g. clicks inside our own popover would otherwise re-trigger).
                guard event.window === pv.window else { return event }
                // Only act on clicks that land inside the PDFView's own frame
                let viewPoint = pv.convert(event.locationInWindow, from: nil)
                guard pv.bounds.contains(viewPoint) else { return event }

                switch self.parent.activeTool {
                case .text:
                    // Place new comment on any area — consume event so PDFKit
                    // doesn't start a text-selection drag instead.
                    pv.showStickyPopover(at: viewPoint, coordinator: self,
                                         existingAnnotation: nil, viewOnly: false)
                    return nil

                case .select:
                    // Intercept taps on existing .text annotations: show our
                    // popover instead of PDFKit's unstyled popup window.
                    if let page = pv.page(for: viewPoint, nearest: false) {
                        let pp = pv.convert(viewPoint, to: page)
                        if let ann = page.annotations.first(where: {
                            $0.type == "Text" && $0.bounds.insetBy(dx: -6, dy: -6).contains(pp)
                        }) {
                            pv.showStickyPopover(at: viewPoint, coordinator: self,
                                                 existingAnnotation: ann, viewOnly: true)
                            return nil
                        }
                    }

                case .signature:
                    if let page = pv.page(for: viewPoint, nearest: true) {
                        let pp = pv.convert(viewPoint, to: page)
                        pv.showSignaturePanel(at: viewPoint, pagePoint: pp, page: page, coordinator: self)
                        return nil
                    }

                default: break
                }
                return event
            }
        }

        func commitComment(text: String, at pagePoint: CGPoint, page: PDFPage,
                           existingAnnotation: PDFAnnotation?) {
            guard !text.isEmpty else { return }
            if let ann = existingAnnotation {
                ann.contents = text
            } else {
                let bounds = CGRect(x: pagePoint.x - 16, y: pagePoint.y - 16, width: 32, height: 32)
                let ann = PDFAnnotation(bounds: bounds, forType: .text, withProperties: nil)
                ann.contents = text
                ann.color    = .systemYellow
                // "Comment" renders as a speech-bubble icon, cleaner than "Note" dog-ear
                ann.setValue("Comment" as NSString,
                             forAnnotationKey: PDFAnnotationKey(rawValue: "/Name"))
                page.addAnnotation(ann)
            }
            parent.onAnnotationAdded()
        }

        func commitSignature(name: String, fontName: String, color: NSColor,
                             at pagePoint: CGPoint, page: PDFPage) {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }

            // Use a freeText annotation: PDFKit gives us native move + resize
            // handles when the user clicks it with the select tool.
            let pointSize: CGFloat = 28
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
            ann.color     = .clear              // transparent background
            let border = PDFBorder()
            border.lineWidth = 0.5              // non-zero so PDFKit renders resize handles
            border.style = .solid
            ann.border    = border
            // Ensure the annotation is editable/movable with the select tool
            ann.isReadOnly = false
            ann.shouldDisplay = true
            ann.shouldPrint   = true
            ann.alignment = .center
            page.addAnnotation(ann)
            parent.onAnnotationAdded()
        }
    }
}

// MARK: - DrawablePDFView
// PDFView subclass that intercepts mouse events for freehand ink drawing,
// shows crosshair cursor, and hosts the inline sticky comment popover.

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
        vc.onCommit = { [weak self, weak coordinator, weak popover] name, fontName, color in
            popover?.close()
            guard let self, let coordinator,
                  let page = self.sigPage else { return }
            coordinator.commitSignature(name: name, fontName: fontName, color: color,
                                        at: self.sigPagePoint, page: page)
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

// MARK: - SignaturePanelViewController
// Popover with a drawing canvas for capturing a handwritten signature.

private final class SignaturePanelViewController: NSViewController {

    var onCommit: ((String, String, NSColor) -> Void)?  // name, fontName, color
    var onCancel: (() -> Void)?

    private let nameField  = NSTextField()
    private let fontPopup  = NSPopUpButton()
    private let colorWell  = NSColorWell()
    private let preview    = NSTextField(labelWithString: "")

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
        let W: CGFloat = 360, H: CGFloat = 230
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

        nameField.frame = NSRect(x: 12, y: H - 88, width: W - 24, height: 22)
        nameField.placeholderString = "Your name"
        nameField.font = .systemFont(ofSize: 13)
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

        // Preview area
        let previewBG = NSView(frame: NSRect(x: 12, y: 12, width: W - 24, height: H - 144))
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
        updatePreview()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        DispatchQueue.main.async { self.view.window?.makeFirstResponder(self.nameField) }
    }

    @objc private func updatePreview() {
        let name = nameField.stringValue.isEmpty ? "Your Name" : nameField.stringValue
        let entry = signatureFonts[fontPopup.indexOfSelectedItem]
        let font  = NSFont(name: entry.fontName, size: 36) ?? .systemFont(ofSize: 36)
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
        onCommit?(name, entry.fontName, colorWell.color)
    }

    @objc private func cancel() { onCancel?() }
    override func cancelOperation(_ sender: Any?) { onCancel?() }
}

extension SignaturePanelViewController: NSTextFieldDelegate {
    func controlTextDidChange(_ obj: Notification) { updatePreview() }
}

// MARK: - SignatureStampAnnotation removed — signatures now use freeText for native edit handles.

