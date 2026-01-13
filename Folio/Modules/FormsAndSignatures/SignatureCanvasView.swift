// SignatureCanvasView.swift
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

// MARK: - SwiftUI Wrapper

/// Freehand signature canvas backed by a custom `NSView`.
/// On mouse-up, exports the drawn path as an `NSImage` via `onSignatureComplete`.
struct SignatureCanvasView: NSViewRepresentable {

    @Binding var signature: NSImage?

    func makeNSView(context: Context) -> SignatureNSCanvas {
        let canvas = SignatureNSCanvas()
        canvas.onSignatureComplete = { image in
            signature = image
        }
        return canvas
    }

    func updateNSView(_ nsView: SignatureNSCanvas, context: Context) {}
}

// MARK: - NSView Canvas

final class SignatureNSCanvas: NSView {

    var onSignatureComplete: ((NSImage) -> Void)?

    private var activePath = NSBezierPath()
    private var allStrokes: [NSBezierPath] = []
    private var isCurrentlyDrawing = false

    // Use flipped coordinates so (0,0) is top-left, matching expectations
    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        // Background
        NSColor.white.setFill()
        NSBezierPath(rect: bounds).fill()

        // Ink
        NSColor.black.setStroke()
        allStrokes.forEach { stroke in
            stroke.lineWidth = 2.0
            stroke.lineCapStyle = .round
            stroke.lineJoinStyle = .round
            stroke.stroke()
        }
        activePath.lineWidth = 2.0
        activePath.lineCapStyle = .round
        activePath.lineJoinStyle = .round
        activePath.stroke()
    }

    // MARK: - Mouse Events

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        activePath = NSBezierPath()
        activePath.move(to: point)
        isCurrentlyDrawing = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard isCurrentlyDrawing else { return }
        let point = convert(event.locationInWindow, from: nil)
        activePath.line(to: point)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard isCurrentlyDrawing else { return }
        isCurrentlyDrawing = false
        allStrokes.append(activePath)
        activePath = NSBezierPath()
        needsDisplay = true
        exportSignature()
    }

    // MARK: - Actions

    func clearCanvas() {
        allStrokes.removeAll()
        activePath = NSBezierPath()
        needsDisplay = true
    }

    private func exportSignature() {
        let image = NSImage(size: bounds.size)
        image.lockFocus()
        draw(bounds)
        image.unlockFocus()
        onSignatureComplete?(image)
    }
}

// MARK: - Signature Manager View

/// Sheet that lets the user draw a signature, then places it on the active PDF page.
struct SignatureManagerView: View {

    var tab: DocumentTab
    @State private var signature: NSImage?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 16) {
            Text("Draw Your Signature")
                .font(.headline)

            SignatureCanvasView(signature: $signature)
                .frame(width: 400, height: 160)
                .border(.separator)
                .cornerRadius(6)

            HStack {
                Button("Clear") {
                    signature = nil
                }

                Spacer()

                Button("Cancel") { dismiss() }

                Button("Apply to Page") {
                    applySignature()
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(signature == nil)
            }
            .padding(.top, 4)
        }
        .padding(24)
        .frame(width: 460)
    }

    private func applySignature() {
        guard let image = signature,
              let page = tab.document.page(at: tab.currentPageIndex) else { return }

        let pageBounds = page.bounds(for: .mediaBox)
        let sigBounds = CGRect(
            x: pageBounds.midX - 100,
            y: pageBounds.midY - 30,
            width: 200,
            height: 60
        )
        let annotation = PDFAnnotation(bounds: sigBounds, forType: .stamp, withProperties: nil)
        annotation.setValue(image, forAnnotationKey: PDFAnnotationKey(rawValue: "/AP"))
        page.addAnnotation(annotation)
    }
}
