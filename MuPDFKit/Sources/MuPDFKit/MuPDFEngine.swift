//  MuPDFEngine.swift
//  MuPDFKit
//
//  Swift wrapper around the MuPDFCore C library.
//  Converts the C API into an idiomatic Swift interface with
//  structured errors, value types, and URL-based file references.

import Foundation
import CoreGraphics
import MuPDFCore

// ---------------------------------------------------------------------------
// MARK: - Error type
// ---------------------------------------------------------------------------

public enum MuPDFError: Error, LocalizedError {
    case openFailed(String)
    case saveFailed(String)
    case imageInsertFailed(String)
    case textExtractionFailed(String)
    case textReplaceFailed(String)
    case invalidPage(Int)

    public var errorDescription: String? {
        switch self {
        case .openFailed(let m):          return "MuPDF open failed: \(m)"
        case .saveFailed(let m):          return "MuPDF save failed: \(m)"
        case .imageInsertFailed(let m):   return "MuPDF image insert failed: \(m)"
        case .textExtractionFailed(let m):return "MuPDF text extraction failed: \(m)"
        case .textReplaceFailed(let m):   return "MuPDF text replace failed: \(m)"
        case .invalidPage(let n):         return "Invalid page index: \(n)"
        }
    }
}

// ---------------------------------------------------------------------------
// MARK: - Value types
// ---------------------------------------------------------------------------

/// A text line extracted from a PDF page, with bounding box in PDF points
/// (origin at bottom-left of the page).
public struct PDFTextLine: Identifiable, Sendable {
    public let id   = UUID()
    public let text : String
    /// Bottom-left x in PDF points (origin = bottom-left of page).
    public let x    : CGFloat
    /// Bottom-left y in PDF points.
    public let y    : CGFloat
    public let width: CGFloat
    public let height: CGFloat
    /// PostScript name of the dominant font on this line.
    public let fontName: String
    /// Font size in PDF points.
    public let fontSize: CGFloat
    /// Text colour components (0–1).
    public let colorR: Float
    public let colorG: Float
    public let colorB: Float

    public var bounds: CGRect { CGRect(x: x, y: y, width: width, height: height) }

    public init(text: String, x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat,
                fontName: String, fontSize: CGFloat,
                colorR: Float, colorG: Float, colorB: Float) {
        self.text = text
        self.x = x; self.y = y
        self.width = width; self.height = height
        self.fontName = fontName; self.fontSize = fontSize
        self.colorR = colorR; self.colorG = colorG; self.colorB = colorB
    }
}

// ---------------------------------------------------------------------------
// MARK: - MuPDFDocument
// ---------------------------------------------------------------------------

/// An open, mutable PDF document backed by libmupdf.
/// This class is NOT thread-safe; use it from one thread/actor at a time.
public final class MuPDFDocument {

    // MuPDFHandle is an incomplete C struct, so Swift imports it as OpaquePointer.
    private var handle: OpaquePointer?

    // MARK: - Init / deinit

    /// Open a PDF from a file URL.
    /// - Throws: `MuPDFError.openFailed` if the file cannot be opened.
    public init(url: URL) throws {
        var errBuf = [CChar](repeating: 0, count: 512)
        guard let h = mupdf_open(url.path, &errBuf) else {
            throw MuPDFError.openFailed(String(cString: errBuf))
        }
        handle = h
    }

    deinit {
        if let h = handle {
            mupdf_close(h)
            handle = nil
        }
    }

    // MARK: - Metadata

    /// The number of pages in the document.
    public var pageCount: Int {
        var errBuf = [CChar](repeating: 0, count: 512)
        let n = mupdf_page_count(handle, &errBuf)
        return n >= 0 ? Int(n) : 0
    }

    // MARK: - Save

    /// Saves the document to a temporary file and returns the raw PDF bytes.
    ///
    /// Use this instead of `save(to:)` when you need to avoid writing directly
    /// to a sandboxed user URL (e.g. ~/Downloads with a read-only bookmark).
    /// The caller is responsible for writing the returned `Data` to its final
    /// destination (e.g. via `DocumentTab.save()` which handles permissions and
    /// NSSavePanel fallback).
    ///
    /// - Throws: `MuPDFError.saveFailed` on any failure.
    public func saveAsData() throws -> Data {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("pdf")
        var errBuf = [CChar](repeating: 0, count: 512)
        guard mupdf_save(handle, tmp.path, &errBuf) == 0 else {
            throw MuPDFError.saveFailed(String(cString: errBuf))
        }
        do {
            let data = try Data(contentsOf: tmp)
            try? FileManager.default.removeItem(at: tmp)
            return data
        } catch {
            throw MuPDFError.saveFailed("temp read failed: \(error.localizedDescription)")
        }
    }

    /// Save the document (including any edits) to a URL.
    ///
    /// The C-level `mupdf_save` writes to a raw path and cannot use
    /// security-scoped bookmarks. To work inside the macOS App Sandbox for
    /// user-chosen files (e.g. in Downloads), we:
    ///   1. Write to a temporary file inside the app's sandbox container
    ///      (no special permissions needed).
    ///   2. Read that data back with Swift.
    ///   3. Write the data to the real destination URL via `Data.write(to:)`
    ///      which *does* honour the active security-scoped resource grant.
    ///
    /// - Throws: `MuPDFError.saveFailed` on any failure.
    public func save(to url: URL) throws {
        // Step 1 – write to a unique temp file.
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("pdf")
        var errBuf = [CChar](repeating: 0, count: 512)
        guard mupdf_save(handle, tmp.path, &errBuf) == 0 else {
            throw MuPDFError.saveFailed(String(cString: errBuf))
        }
        // Step 2 – read the temp data.
        let data: Data
        do {
            data = try Data(contentsOf: tmp)
        } catch {
            throw MuPDFError.saveFailed("temp read failed: \(error.localizedDescription)")
        }
        // Step 3 – overwrite the destination IN-PLACE.
        //
        // In the macOS App Sandbox the user-selected file grant covers the
        // single file the user opened, NOT its parent directory.  This means
        // any technique that creates a temp file *next to* the destination
        // (Data.write(...,.atomic), FileManager.replaceItem, NSFileCoordinator
        // .replace, etc.) fails with EPERM because they need to create the
        // sibling temp file inside e.g. ~/Downloads.
        //
        // The only operation that works under a single-file grant is opening
        // the existing file for write+truncate.  Data.write(to:) without
        // `.atomic` does exactly that – open(O_WRONLY|O_TRUNC), write, close.
        do {
            try data.write(to: url)
        } catch {
            throw MuPDFError.saveFailed("cannot write to destination: \(error.localizedDescription)")
        }
    }

    // MARK: - Image insertion

    /// Embed an image into a page at the given PDF-coordinate rectangle.
    ///
    /// PDF coordinate system: origin at **bottom-left**, units = points.
    /// If you have an AppKit (flipped) rect, convert first via
    /// `MuPDFDocument.convertToPDFCoords(appKitRect:pageHeight:)`.
    ///
    /// - Parameters:
    ///   - imageData: Raw JPEG or PNG bytes.
    ///   - pageIndex: 0-based page number.
    ///   - rect:      Destination in PDF coordinates (bottom-left origin).
    /// - Throws: `MuPDFError.imageInsertFailed` on failure.
    public func insertImage(_ imageData: Data,
                            onPage pageIndex: Int,
                            at rect: CGRect) throws {
        var errBuf = [CChar](repeating: 0, count: 512)
        let result: Int32 = imageData.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            let base = raw.baseAddress!.assumingMemoryBound(to: UInt8.self)
            return mupdf_insert_image(
                handle,
                Int32(pageIndex),
                base,
                imageData.count,
                Float(rect.minX),
                Float(rect.minY),
                Float(rect.width),
                Float(rect.height),
                &errBuf
            )
        }
        if result != 0 {
            throw MuPDFError.imageInsertFailed(String(cString: errBuf))
        }
    }

    // MARK: - Text extraction

    /// Extract all text lines from a page.
    /// Lines are returned in document order; coordinates are PDF points.
    ///
    /// - Parameter pageIndex: 0-based page number.
    /// - Returns: Array of `PDFTextLine` values.
    /// - Throws: `MuPDFError.textExtractionFailed` on failure.
    public func extractTextLines(from pageIndex: Int) throws -> [PDFTextLine] {
        var errBuf = [CChar](repeating: 0, count: 512)
        guard let cjson = mupdf_extract_text_json(handle, Int32(pageIndex), &errBuf) else {
            throw MuPDFError.textExtractionFailed(String(cString: errBuf))
        }
        defer { mupdf_free_string(cjson) }

        let data = Data(bytes: cjson, count: strlen(cjson))
        let decoded = try JSONDecoder().decode([TextLineJSON].self, from: data)
        return decoded.map {
            PDFTextLine(text: $0.text,
                        x: CGFloat($0.x), y: CGFloat($0.y),
                        width: CGFloat($0.w), height: CGFloat($0.h),
                        fontName: $0.font ?? "Helvetica",
                        fontSize: CGFloat($0.fs ?? Float($0.h) * 0.75),
                        colorR: $0.r ?? 0, colorG: $0.g ?? 0, colorB: $0.b ?? 0)
        }
    }

    // MARK: - Text replacement

    /// Replaces the text content inside a bounding box on a page.
    ///
    /// - Parameters:
    ///   - newText:    The replacement string.
    ///   - pageIndex:  0-based page number.
    ///   - rect:       Bounding box in PDF coordinates (origin bottom-left).
    ///   - fontName:   PostScript font name of the original text.
    ///   - fontSize:   Font size in PDF points.
    ///   - colorR/G/B: Text colour components in [0,1].
    /// - Throws: `MuPDFError.textReplaceFailed` on failure.
    public func replaceText(_ newText: String,
                            onPage pageIndex: Int,
                            at rect: CGRect,
                            fontName: String = "Helvetica",
                            fontSize: CGFloat = 0,
                            colorR: Float = 0, colorG: Float = 0, colorB: Float = 0) throws {
        let size = fontSize > 0 ? fontSize : rect.height * 0.75
        var errBuf = [CChar](repeating: 0, count: 512)
        let result = newText.withCString { ctext in
            fontName.withCString { cfont in
                mupdf_replace_text(handle,
                                   Int32(pageIndex),
                                   Float(rect.minX), Float(rect.minY),
                                   Float(rect.width), Float(rect.height),
                                   ctext, cfont, Float(size),
                                   colorR, colorG, colorB,
                                   &errBuf)
            }
        }
        if result != 0 {
            throw MuPDFError.textReplaceFailed(String(cString: errBuf))
        }
    }

    // MARK: - Coordinate helpers

    /// Convert an AppKit screen rect (origin top-left, flipped Y) into
    /// PDF coordinates (origin bottom-left) given the page height in points.
    public static func convertToPDFCoords(appKitRect r: CGRect,
                                          pageHeight: CGFloat) -> CGRect {
        let pdfY = pageHeight - r.origin.y - r.size.height
        return CGRect(x: r.origin.x, y: pdfY,
                      width: r.size.width, height: r.size.height)
    }
}

// ---------------------------------------------------------------------------
// MARK: - JSON decoding helpers (private)
// ---------------------------------------------------------------------------

private struct TextLineJSON: Decodable {
    let text: String
    let x, y, w, h: Float
    let font: String?
    let fs: Float?
    let r: Float?
    let g: Float?
    let b: Float?
}
