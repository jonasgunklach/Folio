// CorePDFEngine.swift
// Folio
//
// MIT License
// Copyright (c) 2026 Folio Contributors
//
// App Store safe replacement for MuPDFKit.
// Uses PDFKit and Core Graphics only — no third-party libraries required.
//
// Implements the same three operations that were previously handled by libmupdf:
//   1. Image insertion  — CGContext-based PDF redraw with CGImage injection
//   2. Text replacement — CGContext-based PDF redraw with white-rect cover + Core Text
//   3. Text extraction  — PDFKit characterBounds(at:) + attributedString font metadata

import Foundation
import CoreGraphics
import PDFKit
import AppKit
import CoreText

// MARK: - PDFTextLine

/// A text line extracted from a PDF page, with bounding box in PDF points
/// (origin at bottom-left of the page, Y increases upward).
struct PDFTextLine: Identifiable, Sendable {
    let id = UUID()
    let text: String
    let x: CGFloat
    let y: CGFloat
    let width: CGFloat
    let height: CGFloat
    /// PostScript font name (e.g. "Helvetica-Bold").
    let fontName: String
    /// Font size in PDF points.
    let fontSize: CGFloat
    /// Text colour components in [0, 1].
    let colorR: Float
    let colorG: Float
    let colorB: Float

    var bounds: CGRect { CGRect(x: x, y: y, width: width, height: height) }

    init(text: String, x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat,
         fontName: String, fontSize: CGFloat,
         colorR: Float, colorG: Float, colorB: Float) {
        self.text = text
        self.x = x; self.y = y
        self.width = width; self.height = height
        self.fontName = fontName; self.fontSize = fontSize
        self.colorR = colorR; self.colorG = colorG; self.colorB = colorB
    }
}

// MARK: - CorePDFError

enum CorePDFError: Error, LocalizedError {
    case openFailed(String)
    case saveFailed(String)
    case imageInsertFailed(String)
    case textExtractionFailed(String)
    case textReplaceFailed(String)
    case invalidPage(Int)

    var errorDescription: String? {
        switch self {
        case .openFailed(let m):           return "CorePDF open failed: \(m)"
        case .saveFailed(let m):           return "CorePDF save failed: \(m)"
        case .imageInsertFailed(let m):    return "CorePDF image insert failed: \(m)"
        case .textExtractionFailed(let m): return "CorePDF text extraction failed: \(m)"
        case .textReplaceFailed(let m):    return "CorePDF text replace failed: \(m)"
        case .invalidPage(let n):          return "Invalid page index: \(n)"
        }
    }
}

// MARK: - CorePDFDocument

/// App Store safe PDF document engine backed by PDFKit and Core Graphics.
/// Drop-in replacement for the removed MuPDFDocument type.
///
/// Mutations (image insertion, text replacement) are queued in-memory and
/// applied together when `saveAsData()` or `save(to:)` is called.
/// The source file is never modified until an explicit save.
final class CorePDFDocument {

    private let sourceData: Data

    // Queued per-page mutations. Key = 0-based page index.
    // Each closure receives a CGContext already positioned for that page.
    private var pageMutations: [Int: [(CGContext) -> Void]] = [:]

    // MARK: - Init

    init(url: URL) throws {
        guard let data = try? Data(contentsOf: url) else {
            throw CorePDFError.openFailed("Could not read file: \(url.lastPathComponent)")
        }
        guard let provider = CGDataProvider(data: data as CFData),
              CGPDFDocument(provider) != nil else {
            throw CorePDFError.openFailed("Not a valid PDF: \(url.lastPathComponent)")
        }
        self.sourceData = data
    }

    // MARK: - Metadata

    var pageCount: Int {
        guard let provider = CGDataProvider(data: sourceData as CFData),
              let doc = CGPDFDocument(provider) else { return 0 }
        return doc.numberOfPages
    }

    // MARK: - Image Insertion

    /// Embed an image onto a page at the given PDF-coordinate rectangle.
    ///
    /// PDF coordinate system: origin at bottom-left, Y increases upward, units = points.
    /// If you have an AppKit rect, convert with `convertToPDFCoords(appKitRect:pageHeight:)`.
    ///
    /// - Parameters:
    ///   - imageData: Raw JPEG or PNG bytes.
    ///   - pageIndex: 0-based page number.
    ///   - rect:      Destination rectangle in PDF coordinates.
    func insertImage(_ imageData: Data, onPage pageIndex: Int, at rect: CGRect) throws {
        guard let source = CGImageSourceCreateWithData(imageData as CFData, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw CorePDFError.imageInsertFailed("Could not decode image data")
        }
        let img = cgImage
        let r = rect
        let imageMutation: (CGContext) -> Void = { ctx in
            // In a Y-up PDF context, CGContext.draw(_:in:) places pixel row 0
            // at the bottom of the rect (upside-down). Apply a flip so the
            // image renders right-side up, matching PDF convention.
            ctx.saveGState()
            ctx.translateBy(x: r.minX, y: r.minY + r.height)
            ctx.scaleBy(x: 1.0, y: -1.0)
            ctx.draw(img, in: CGRect(x: 0, y: 0, width: r.width, height: r.height))
            ctx.restoreGState()
        }
        pageMutations[pageIndex, default: []].append(imageMutation)
    }

    // MARK: - Text Replacement

    /// Replace the text inside a bounding rectangle on a page.
    ///
    /// Covers the original content with a white opaque rectangle, then draws
    /// the replacement text using Core Text — identical in effect to the
    /// previous MuPDF-based implementation.
    ///
    /// - Parameters:
    ///   - newText:   The replacement string.
    ///   - pageIndex: 0-based page number.
    ///   - rect:      Bounding box in PDF coordinates (origin bottom-left).
    ///   - fontName:  PostScript font name (e.g. "Helvetica", "Times-Roman").
    ///   - fontSize:  Font size in points. Pass 0 to auto-derive from rect height.
    ///   - colorR/G/B: Text colour components in [0, 1].
    func replaceText(_ newText: String,
                     onPage pageIndex: Int,
                     at rect: CGRect,
                     fontName: String = "Helvetica",
                     fontSize: CGFloat = 0,
                     colorR: Float = 0, colorG: Float = 0, colorB: Float = 0) throws {
        let size = fontSize > 0 ? fontSize : rect.height * 0.75
        let capturedText = newText
        let capturedRect = rect
        let capturedFont = fontName
        let capturedSize = size
        let capturedR = colorR, capturedG = colorG, capturedB = colorB

        let textMutation: (CGContext) -> Void = { ctx in
            // Step 1: Cover the original text with a white opaque rectangle.
            ctx.saveGState()
            ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
            ctx.fill(capturedRect)
            ctx.restoreGState()

            // Step 2: Draw replacement text via CTLineDraw with pure CT/CG attributes.
            //
            // IMPORTANT: Do NOT use NSFont / NSColor attributes here. Those rely on
            // [NSFont set] / [NSColor set] which require an active NSGraphicsContext.
            // A bare CGContext-based PDF output has no NSGraphicsContext, so using
            // NS-level attributes corrupts the context state for the rest of the
            // document. Use kCTFontAttributeName (CTFont) and kCTForegroundColorAttributeName
            // (CGColor) instead — these operate entirely at the CG/CT layer.
            ctx.saveGState()
            // CTFontCreateWithName silently substitutes when a PDF embedded font
            // name (e.g. "ABCDEF+Helvetica") isn't installed. Strip the subset
            // prefix (everything up to and including "+") to maximise the chance
            // of matching the base face that IS installed.
            let baseFontName: String
            if let plusIdx = capturedFont.firstIndex(of: "+") {
                baseFontName = String(capturedFont[capturedFont.index(after: plusIdx)...])
            } else {
                baseFontName = capturedFont
            }
            let ctFont  = CTFontCreateWithName(baseFontName as CFString, capturedSize, nil)
            let cgColor = CGColor(red:   CGFloat(capturedR),
                                  green: CGFloat(capturedG),
                                  blue:  CGFloat(capturedB),
                                  alpha: 1.0)
            let ctAttrs: [NSAttributedString.Key: Any] = [
                NSAttributedString.Key(kCTFontAttributeName as String):            ctFont,
                NSAttributedString.Key(kCTForegroundColorAttributeName as String): cgColor
            ]
            let attrStr = NSAttributedString(string: capturedText, attributes: ctAttrs)
            let line    = CTLineCreateWithAttributedString(attrStr)
            // Reset text matrix — required in PDF CGContexts to avoid inheriting
            // a stale transform from drawPDFPage.
            ctx.textMatrix = .identity
            // Place the baseline using the font's actual descent metric so the
            // replacement text sits at the same vertical position as the original.
            // CTFontGetDescent returns a positive value (distance below baseline).
            let descent = CTFontGetDescent(ctFont)
            ctx.textPosition = CGPoint(x: capturedRect.minX,
                                       y: capturedRect.minY + descent)
            CTLineDraw(line, ctx)
            ctx.restoreGState()
        }
        pageMutations[pageIndex, default: []].append(textMutation)
    }

    // MARK: - Persistence

    /// Renders all queued mutations and returns the result as PDF bytes.
    ///
    /// The algorithm:
    ///   1. Re-open the original PDF as a `CGPDFDocument`.
    ///   2. Create an in-memory PDF `CGContext`.
    ///   3. For each page: draw the existing content, then apply mutations.
    ///   4. Close the context and return the accumulated bytes.
    func saveAsData() throws -> Data {
        guard let provider = CGDataProvider(data: sourceData as CFData),
              let srcDoc = CGPDFDocument(provider) else {
            throw CorePDFError.saveFailed("Could not re-open source PDF")
        }

        let mutableOutput = NSMutableData()
        guard let consumer = CGDataConsumer(data: mutableOutput) else {
            throw CorePDFError.saveFailed("Could not create CGDataConsumer")
        }

        var zeroBox = CGRect.zero
        guard let ctx = CGContext(consumer: consumer, mediaBox: &zeroBox, nil) else {
            throw CorePDFError.saveFailed("Could not create PDF CGContext")
        }

        for i in 1...srcDoc.numberOfPages {
            guard let page = srcDoc.page(at: i) else { continue }
            let box = page.getBoxRect(.mediaBox)
            // kCGPDFContextMediaBox requires CFData containing raw CGRect bytes,
            // not NSValue — use withUnsafeBytes to produce the correct CFData.
            let boxData = withUnsafeBytes(of: box) { Data($0) } as CFData
            let pageInfo = [kCGPDFContextMediaBox as String: boxData] as CFDictionary
            ctx.beginPDFPage(pageInfo)

            // Draw existing page content inside a saved graphics state so that
            // our mutations always start with a clean, unmodified transform.
            ctx.saveGState()
            ctx.drawPDFPage(page)
            ctx.restoreGState()

            // Apply queued mutations for this page (page index is 0-based here).
            for mutation in pageMutations[i - 1] ?? [] {
                mutation(ctx)
            }

            ctx.endPDFPage()
        }

        ctx.closePDF()

        let outputData = mutableOutput as Data
        guard !outputData.isEmpty else {
            throw CorePDFError.saveFailed("PDF context produced empty output")
        }
        return outputData
    }

    /// Save the document to a URL using the same in-place write strategy as
    /// the previous MuPDF implementation (open(O_WRONLY|O_TRUNC) without atomic
    /// rename, which is required for single-file sandbox grants).
    func save(to url: URL) throws {
        let data = try saveAsData()
        do {
            try data.write(to: url)
        } catch {
            throw CorePDFError.saveFailed("Cannot write to destination: \(error.localizedDescription)")
        }
    }

    // MARK: - Text Extraction

    /// Extract all text lines from a PDFKit page with per-line font metadata.
    ///
    /// Uses `PDFPage.characterBounds(at:)` (macOS 10.14+) for precise per-character
    /// bounding boxes, and `PDFPage.attributedString` for font name, size, and colour.
    /// Characters are grouped into lines by Y-coordinate proximity.
    ///
    /// Returned coordinates are in PDF page space (origin bottom-left, points).
    ///
    /// - Parameter page: The PDFKit page to extract text from.
    /// - Returns: Array of `PDFTextLine` values in top-to-bottom, left-to-right order.
    static func extractTextLines(from page: PDFPage) -> [PDFTextLine] {
        guard let attrStr = page.attributedString else { return [] }
        let nsStr = attrStr.string as NSString
        let count = nsStr.length
        guard count > 0 else { return [] }

        struct CharInfo {
            let char:     String
            let bounds:   CGRect
            let font:     NSFont
            let color:    NSColor
            /// Approximate baseline Y in PDF coordinates (bottom-left origin, Y up).
            /// We use bounds.minY rather than midY because characters on the same
            /// text line share a common baseline descent regardless of glyph height,
            /// while their midY values diverge (capitals vs. descenders, mixed sizes,
            /// superscripts, etc.).
            var baselineY: CGFloat { bounds.minY }
        }

        var chars: [CharInfo] = []
        chars.reserveCapacity(count)

        for i in 0..<count {
            let ch = nsStr.substring(with: NSRange(location: i, length: 1))
            guard ch != "\n" && ch != "\r" && ch != "\t" else { continue }
            let b = page.characterBounds(at: i)
            guard !b.isEmpty && b.width > 0 else { continue }
            let font  = attrStr.attribute(.font,            at: i, effectiveRange: nil) as? NSFont  ?? NSFont.systemFont(ofSize: 12)
            let color = attrStr.attribute(.foregroundColor, at: i, effectiveRange: nil) as? NSColor ?? NSColor.black
            chars.append(CharInfo(char: ch, bounds: b, font: font, color: color))
        }

        guard !chars.isEmpty else { return [] }

        // Sort top-to-bottom (higher PDF Y = higher on page), then left-to-right.
        // Use baselineY so that mixed-size chars on the same line sort together.
        chars.sort { a, b in
            // Threshold for "same line" during sort: half the smaller glyph height.
            let lineThreshold = min(a.bounds.height, b.bounds.height) * 0.5
            let dy = abs(a.baselineY - b.baselineY)
            if dy > lineThreshold { return a.baselineY > b.baselineY }
            return a.bounds.minX < b.bounds.minX
        }

        // --- Line grouping --------------------------------------------------
        // Group characters whose baseline Y values are within a font-relative
        // tolerance of each other. We track the *median* baseline of each
        // growing bucket rather than the first character's baseline, so
        // superscripts / subscripts don't prematurely split a line.

        var lines: [PDFTextLine] = []
        var bucket: [CharInfo] = []

        func bucketBaselineY() -> CGFloat {
            // Median baseline of the current bucket — robust to outliers.
            let ys = bucket.map(\.baselineY).sorted()
            return ys[ys.count / 2]
        }

        func flushBucket() {
            guard !bucket.isEmpty else { return }
            let text = bucket.map(\.char).joined().trimmingCharacters(in: .whitespaces)
            guard !text.isEmpty else { bucket = []; return }

            let unionRect = bucket.reduce(CGRect.null) { $0.union($1.bounds) }
            let dominant  = bucket.max(by: { $0.font.pointSize < $1.font.pointSize })!
            let rgb = dominant.color.usingColorSpace(.deviceRGB) ?? NSColor.black
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            rgb.getRed(&r, green: &g, blue: &b, alpha: &a)

            lines.append(PDFTextLine(
                text:      text,
                x:         unionRect.minX,
                y:         unionRect.minY,
                width:     unionRect.width,
                height:    unionRect.height,
                fontName:  dominant.font.fontName,
                fontSize:  dominant.font.pointSize,
                colorR:    Float(r),
                colorG:    Float(g),
                colorB:    Float(b)
            ))
            bucket = []
        }

        for ch in chars {
            if bucket.isEmpty {
                bucket.append(ch)
                continue
            }
            // Threshold = half the current dominant glyph height in the bucket.
            // This scales automatically: 3 pts for 6pt text, 18 pts for 36pt headings.
            let domHeight = bucket.map { $0.bounds.height }.max() ?? ch.bounds.height
            let threshold = domHeight * 0.5

            if abs(ch.baselineY - bucketBaselineY()) <= threshold {
                bucket.append(ch)
            } else {
                flushBucket()
                bucket.append(ch)
            }
        }
        flushBucket()

        return lines
    }

    // MARK: - Coordinate Helpers

    /// Convert an AppKit rect (origin top-left, Y increases downward) to
    /// PDF coordinates (origin bottom-left, Y increases upward).
    static func convertToPDFCoords(appKitRect r: CGRect, pageHeight: CGFloat) -> CGRect {
        CGRect(
            x:      r.origin.x,
            y:      pageHeight - r.origin.y - r.size.height,
            width:  r.size.width,
            height: r.size.height
        )
    }
}
