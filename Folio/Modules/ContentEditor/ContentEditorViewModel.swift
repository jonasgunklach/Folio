// ContentEditorViewModel.swift
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

import Foundation
import PDFKit
import AppKit

/// Direct PDF content editing backed by libmupdf.
///
/// Operations that require modifying actual page content streams
/// (image insertion, text extraction) are delegated to MuPDF.
/// PDFKit annotations (links, stamps) are still used for overlay
/// operations that don't require stream-level access.
@MainActor
@Observable
final class ContentEditorViewModel {

    // MARK: - State

    var isEditing: Bool = false
    var pendingLinkURL: String = ""
    var lastError: ContentEditorError?
    var isWorking: Bool = false

    // MARK: - Image insertion (MuPDF)

    /// Embeds an image as a real PDF content-stream object on a page.
    ///
    /// - Parameters:
    ///   - image:      The image to embed.
    ///   - documentURL: The file URL of the open document (needed for MuPDF).
    ///   - pageIndex:  0-based page number.
    ///   - rect:       Target bounds in PDFKit coordinates (origin top-left,
    ///                 PDF points relative to the page).
    ///   - pageHeight: Height of the page in PDF points (for coordinate flip).
    func insertImage(_ image: NSImage,
                     documentURL: URL,
                     pageIndex: Int,
                     rect: CGRect,
                     pageHeight: CGFloat,
                     completion: (@MainActor () -> Void)? = nil) {
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            lastError = .imageCodingFailed
            return
        }

        isWorking = true
        lastError = nil

        Task { @MainActor [weak self] in
            guard let self else { return }
            // Re-enter the security scope so the sandbox allows the write back to the URL.
            let accessing = documentURL.startAccessingSecurityScopedResource()
            defer { if accessing { documentURL.stopAccessingSecurityScopedResource() } }

            do {
                let doc = try CorePDFDocument(url: documentURL)
                let pdfRect = CorePDFDocument.convertToPDFCoords(
                    appKitRect: rect, pageHeight: pageHeight)
                try doc.insertImage(pngData, onPage: pageIndex, at: pdfRect)
                try doc.save(to: documentURL)
                isWorking = false
                completion?()
            } catch let e as CorePDFError {
                isWorking = false
                lastError = .muPDFError(e.localizedDescription)
            } catch {
                isWorking = false
                lastError = .muPDFError(error.localizedDescription)
            }
        }
    }

    // MARK: - Text replacement (MuPDF)

    /// Replaces the text at `rect` (PDF coords, origin bottom-left) on the given page
    /// with `newText`, preserving the original font and colour, then calls `completion`
    /// with the modified PDF bytes on success. The caller is responsible for writing
    /// those bytes to disk (routing through `DocumentTab.save()` so that sandbox
    /// permissions and NSSavePanel fallback are handled correctly).
    func replaceText(_ newText: String,
                     documentURL: URL,
                     pageIndex: Int,
                     rect: CGRect,
                     fontName: String,
                     fontSize: CGFloat,
                     colorR: Float,
                     colorG: Float,
                     colorB: Float,
                     completion: (@MainActor (Data) -> Void)? = nil) {
        isWorking = true
        lastError = nil

        Task { @MainActor [weak self] in
            guard let self else { return }
            let accessing = documentURL.startAccessingSecurityScopedResource()
            defer { if accessing { documentURL.stopAccessingSecurityScopedResource() } }

            do {
                let doc = try CorePDFDocument(url: documentURL)
                try doc.replaceText(newText, onPage: pageIndex, at: rect,
                                    fontName: fontName, fontSize: fontSize,
                                    colorR: colorR, colorG: colorG, colorB: colorB)
                // Return raw bytes — DocumentTab.save() handles writing to the sandbox URL.
                let savedData = try doc.saveAsData()
                isWorking = false
                completion?(savedData)
            } catch let e as CorePDFError {
                isWorking = false
                lastError = .muPDFError(e.localizedDescription)
            } catch {
                isWorking = false
                lastError = .muPDFError(error.localizedDescription)
            }
        }
    }

    // MARK: - Text extraction (MuPDF)

    /// Extracts all text lines from a page using MuPDF's structured text engine.
    /// Returns results via the completion closure on the main actor.
    func extractTextLines(documentURL: URL,
                          pageIndex: Int,
                          completion: @escaping @MainActor ([PDFTextLine]) -> Void) {
        isWorking = true
        lastError = nil

        Task { @MainActor [weak self] in
            guard let self else { return }
            let accessing = documentURL.startAccessingSecurityScopedResource()
            defer { if accessing { documentURL.stopAccessingSecurityScopedResource() } }
            if let pdfDoc = PDFDocument(url: documentURL),
               let page = pdfDoc.page(at: pageIndex) {
                let lines = CorePDFDocument.extractTextLines(from: page)
                isWorking = false
                completion(lines)
            } else {
                isWorking = false
                lastError = .muPDFError("Could not open PDF page at index \(pageIndex)")
                completion([])
            }
        }
    }

    // MARK: - Hyperlink insertion (PDFKit)

    /// Inserts a URL-action annotation over the given bounds on a page.
    func insertLink(urlString: String, on page: PDFPage, bounds: CGRect) {
        guard let url = URL(string: urlString) else {
            lastError = .invalidURL(urlString)
            return
        }
        let annotation = PDFAnnotation(bounds: bounds, forType: .link, withProperties: nil)
        annotation.action = PDFActionURL(url: url)
        page.addAnnotation(annotation)
    }
}

// MARK: - Errors

enum ContentEditorError: LocalizedError, Equatable {
    case invalidURL(String)
    case imageCodingFailed
    case muPDFError(String)
    case pageNotFound

    var errorDescription: String? {
        switch self {
        case .invalidURL(let url):    "'\(url)' is not a valid URL."
        case .imageCodingFailed:      "Failed to encode image as PNG."
        case .muPDFError(let detail): "MuPDF error: \(detail)"
        case .pageNotFound:           "The specified page could not be found."
        }
    }
}
