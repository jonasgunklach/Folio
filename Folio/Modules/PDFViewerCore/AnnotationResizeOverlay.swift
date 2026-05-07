// AnnotationResizeOverlay.swift
// Folio
//
// Full-frame NSView subview of PDFView.  Intercepts mouse only over handles/body.
// Drawing always derives positions from pdfView.convert(_:from:) so handles
// stay correct through scroll and zoom without any frame bookkeeping.

import AppKit
import PDFKit

// MARK: - Handle

private enum Handle: CaseIterable {
    case topLeft, top, topRight
    case left,          right
    case bottomLeft, bottom, bottomRight

    var cursor: NSCursor {
        switch self {
        case .top, .bottom:             return .resizeUpDown
        case .left, .right:             return .resizeLeftRight
        case .topLeft, .bottomRight,
             .topRight, .bottomLeft:    return .crosshair
        }
    }
}

// MARK: - AnnotationResizeOverlay

/// Drop into a PDFView as a full-bounds subview.  Call `select(_:pdfView:)` to show
/// handles around an annotation; `deselect()` to hide.
final class AnnotationResizeOverlay: NSView {

    // MARK: Public

    private(set) var selectedAnnotation: PDFAnnotation?
    private weak var pdfView: PDFView?
    var onChanged: (() -> Void)?

    func select(_ annotation: PDFAnnotation, pdfView: PDFView) {
        selectedAnnotation = annotation
        self.pdfView = pdfView
        isHidden = false
        needsDisplay = true
        window?.makeFirstResponder(self)
        startObserving(pdfView)
    }

    func deselect() {
        selectedAnnotation = nil
        pdfView = nil
        isHidden = true
        needsDisplay = true
        stopObserving()
    }

    /// Called from updateNSView — just triggers a redraw.
    func refreshFrame(pdfView: PDFView) {
        needsDisplay = true
    }

    // MARK: Notifications (keep handles in sync with scroll / zoom)

    private var observers: [Any] = []

    private func startObserving(_ pdfView: PDFView) {
        stopObserving()
        let nc = NotificationCenter.default
        let redraw: (Notification) -> Void = { [weak self] _ in
            guard let self else { return }
            self.needsDisplay = true
            if let w = self.window { w.invalidateCursorRects(for: self) }
        }
        observers = [
            nc.addObserver(forName: NSScrollView.didLiveScrollNotification,
                           object: nil, queue: .main, using: redraw),
            nc.addObserver(forName: .PDFViewScaleChanged,
                           object: pdfView, queue: .main, using: redraw),
            nc.addObserver(forName: .PDFViewPageChanged,
                           object: pdfView, queue: .main, using: redraw),
        ]
    }

    private func stopObserving() {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers = []
    }

    deinit { stopObserving() }

    // MARK: Annotation rect in PDFView / overlay coordinate space

    private func annotationRect() -> CGRect? {
        guard let ann = selectedAnnotation,
              let page = ann.page,
              let pv = pdfView else { return nil }
        return pv.convert(ann.bounds, from: page)
    }

    // MARK: Hit testing — pass through everywhere except handles and body

    private let hitR: CGFloat = 12     // half-size of handle hit area

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard !isHidden, let rect = annotationRect() else { return nil }
        let outer = rect.insetBy(dx: -10, dy: -10)
        for h in Handle.allCases {
            let c = handleCenter(h, in: outer)
            if NSRect(x: c.x - hitR, y: c.y - hitR,
                      width: hitR * 2, height: hitR * 2).contains(point) { return self }
        }
        return outer.contains(point) ? self : nil
    }

    // MARK: Drawing

    private let handleR: CGFloat   = 5
    private let fillCol             = NSColor.white
    private let borderCol           = NSColor(calibratedRed: 0.15, green: 0.45, blue: 1.0, alpha: 1.0)

    override func draw(_ dirtyRect: NSRect) {
        guard let rect = annotationRect() else { return }
        let outer = rect.insetBy(dx: -10, dy: -10)

        // Dashed selection border
        let path = NSBezierPath(rect: outer)
        path.lineWidth = 1.5
        path.setLineDash([5, 4], count: 2, phase: 0)
        borderCol.setStroke()
        path.stroke()

        // 8 handles
        for h in Handle.allCases {
            let c = handleCenter(h, in: outer)
            let r = NSRect(x: c.x - handleR, y: c.y - handleR,
                           width: handleR * 2, height: handleR * 2)
            let circle = NSBezierPath(ovalIn: r)
            fillCol.setFill();   circle.fill()
            borderCol.setStroke(); circle.lineWidth = 1.5; circle.stroke()
        }
    }

    // MARK: Mouse interaction

    private var activeHandle: Handle?   = nil
    private var bodyDragging: Bool      = false
    private var dragOrigin: CGPoint     = .zero     // in overlay = PDFView coords
    private var startBounds: CGRect     = .zero     // annotation bounds in PDF coords
    // For body-dragging native .line annotations we need to track the initial
    // startPoint/endPoint (page space) so we can offset them as the drag proceeds.
    private var startStartPoint: CGPoint = .zero
    private var startEndPoint:   CGPoint = .zero

    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        let pt = convert(event.locationInWindow, from: nil)
        guard let rect = annotationRect() else { return }
        let outer = rect.insetBy(dx: -10, dy: -10)

        // Handle hit?
        for h in Handle.allCases {
            let c = handleCenter(h, in: outer)
            if NSRect(x: c.x - hitR, y: c.y - hitR,
                      width: hitR * 2, height: hitR * 2).contains(pt) {
                activeHandle = h
                bodyDragging = false
                dragOrigin   = pt
                startBounds  = selectedAnnotation?.bounds ?? .zero
                return
            }
        }
        // Body drag?
        if outer.contains(pt) {
            bodyDragging = true
            activeHandle = nil
            dragOrigin   = pt
            startBounds  = selectedAnnotation?.bounds ?? .zero
            if let ann = selectedAnnotation, ann.type == "Line" {
                startStartPoint = ann.startPoint
                startEndPoint   = ann.endPoint
            }
            return
        }
        // Outside — deselect and forward
        deselect()
        pdfView?.mouseDown(with: event)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let ann = selectedAnnotation,
              let pv  = pdfView,
              let page = ann.page,
              activeHandle != nil || bodyDragging else { return }

        let pt  = convert(event.locationInWindow, from: nil)
        let dvx = pt.x - dragOrigin.x      // delta in overlay/PDFView pixels
        let dvy = pt.y - dragOrigin.y

        // 1 PDF point expressed in view pixels (accounts for zoom and flipping)
        let vA  = pv.convert(CGPoint.zero,         from: page)
        let vB  = pv.convert(CGPoint(x: 1, y: 1),  from: page)
        let sx  = vB.x - vA.x
        let sy  = vB.y - vA.y
        guard abs(sx) > 1e-4, abs(sy) > 1e-4 else { return }

        // Delta in PDF coordinate space (origin bottom-left, y up)
        let pdx = dvx / sx
        let pdy = dvy / sy

        var r  = startBounds
        let mn: CGFloat = 10

        if bodyDragging {
            r = r.offsetBy(dx: pdx, dy: pdy)
        } else if let h = activeHandle {
            switch h {

            // ── Cardinal ─────────────────────────────────────────────────────
            case .top:
                // top edge moves; origin (bottom) fixed
                r.size.height = max(mn, r.height + pdy)

            case .bottom:
                // bottom edge moves; top fixed
                let newH = max(mn, r.height - pdy)
                r.origin.y   += r.height - newH
                r.size.height = newH

            case .right:
                r.size.width  = max(mn, r.width + pdx)

            case .left:
                let newW = max(mn, r.width - pdx)
                r.origin.x  += r.width - newW
                r.size.width  = newW

            // ── Corners ───────────────────────────────────────────────────────
            case .topRight:
                r.size.height = max(mn, r.height + pdy)
                r.size.width  = max(mn, r.width  + pdx)

            case .topLeft:
                r.size.height = max(mn, r.height + pdy)
                let newW = max(mn, r.width - pdx)
                r.origin.x  += r.width - newW
                r.size.width  = newW

            case .bottomRight:
                let newH = max(mn, r.height - pdy)
                r.origin.y  += r.height - newH
                r.size.height = newH
                r.size.width  = max(mn, r.width + pdx)

            case .bottomLeft:
                let newH = max(mn, r.height - pdy)
                r.origin.y  += r.height - newH
                r.size.height = newH
                let newW = max(mn, r.width - pdx)
                r.origin.x  += r.width  - newW
                r.size.width  = newW
            }
        }

        ann.bounds = r
        if ann.type == "Line" {
            if bodyDragging {
                // Offset the original start/end points by the same page-space delta.
                ann.startPoint = CGPoint(x: startStartPoint.x + pdx, y: startStartPoint.y + pdy)
                ann.endPoint   = CGPoint(x: startEndPoint.x   + pdx, y: startEndPoint.y   + pdy)
            } else {
                // Handle resize: keep endpoints at left/right midpoints of new bounds.
                ann.startPoint = CGPoint(x: r.minX, y: r.midY)
                ann.endPoint   = CGPoint(x: r.maxX, y: r.midY)
            }
        }
        needsDisplay = true
        pv.setNeedsDisplay(pv.bounds)
        onChanged?()
    }

    override func mouseUp(with event: NSEvent) {
        activeHandle = nil
        bodyDragging = false
    }

    // MARK: Cursor rects

    override func resetCursorRects() {
        guard let rect = annotationRect() else { return }
        let outer = rect.insetBy(dx: -10, dy: -10)
        for h in Handle.allCases {
            let c = handleCenter(h, in: outer)
            addCursorRect(NSRect(x: c.x - hitR, y: c.y - hitR,
                                 width: hitR * 2, height: hitR * 2),
                          cursor: h.cursor)
        }
        if !outer.isEmpty { addCursorRect(outer, cursor: .openHand) }
    }

    // MARK: Delete key

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 51 || event.keyCode == 117 {
            if let ann = selectedAnnotation, let page = ann.page {
                page.removeAnnotation(ann)
                deselect()
                onChanged?()
            }
            return
        }
        super.keyDown(with: event)
    }

    // MARK: Handle geometry (in view/overlay coordinate space)

    private func handleCenter(_ h: Handle, in rect: CGRect) -> CGPoint {
        switch h {
        case .topLeft:     return CGPoint(x: rect.minX, y: rect.maxY)
        case .top:         return CGPoint(x: rect.midX, y: rect.maxY)
        case .topRight:    return CGPoint(x: rect.maxX, y: rect.maxY)
        case .left:        return CGPoint(x: rect.minX, y: rect.midY)
        case .right:       return CGPoint(x: rect.maxX, y: rect.midY)
        case .bottomLeft:  return CGPoint(x: rect.minX, y: rect.minY)
        case .bottom:      return CGPoint(x: rect.midX, y: rect.minY)
        case .bottomRight: return CGPoint(x: rect.maxX, y: rect.minY)
        }
    }
}
