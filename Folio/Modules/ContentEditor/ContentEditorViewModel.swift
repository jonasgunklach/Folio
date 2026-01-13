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

/// Provides hooks for direct PDF content editing:
/// text modification, image management, and hyperlink insertion.
///
/// - Note: Full PDF content editing (reflow, font substitution) requires generating
///   a modified PDF byte stream. This ViewModel provides the surface area
///   and will be backed by a CGPDFDocument + CoreGraphics rendering pipeline.
@MainActor
@Observable
final class ContentEditorViewModel {

    // MARK: - State

    var isEditing: Bool = false
    var selectedImageBounds: CGRect?
    var pendingLinkURL: String = ""
    var lastError: ContentEditorError?

    // MARK: - Text Editing (Stub)

    /// Attempts to locate and replace a text string on the given page.
    /// Full implementation requires PDFKit's page drawing pipeline + CGContext rewrite.
    func replaceText(_ original: String, with replacement: String, on page: PDFPage) {
        // TODO: Implement via PDFPage custom drawing override
        // Phase 1: locate glyphs via PDFSelection
        // Phase 2: redact original region with background color
        // Phase 3: draw replacement string at same bounds using Core Text
        lastError = .notYetImplemented("Text replacement requires Core Text integration.")
    }

    // MARK: - Image Management (Stub)

    /// Extracts all images from a page as NSImage objects.
    func extractImages(from page: PDFPage) -> [NSImage] {
        // TODO: Walk the page's content stream via CGPDFContentStream,
        // enumerate image XObjects, and decode via CGPDFDataFormat.
        return []
    }

    /// Inserts an image onto a page at the specified bounds.
    func insertImage(_ image: NSImage, on page: PDFPage, at bounds: CGRect) {
        // TODO: Create a PDFAnnotation of type .stamp with the image,
        // or embed via CGContext during page rendering.
        let imageAnnotation = PDFAnnotation(bounds: bounds, forType: .stamp, withProperties: nil)
        imageAnnotation.setValue(image, forAnnotationKey: PDFAnnotationKey(rawValue: "/AP"))
        page.addAnnotation(imageAnnotation)
    }

    // MARK: - Hyperlink Insertion

    /// Inserts a URL action annotation over the given bounds on a page.
    func insertLink(urlString: String, on page: PDFPage, bounds: CGRect) {
        guard let url = URL(string: urlString) else {
            lastError = .invalidURL(urlString)
            return
        }
        let annotation = PDFAnnotation(bounds: bounds, forType: .link, withProperties: nil)
        let action = PDFActionURL(url: url)
        annotation.action = action
        page.addAnnotation(annotation)
    }
}

// MARK: - Errors

enum ContentEditorError: LocalizedError, Equatable {
    case notYetImplemented(String)
    case invalidURL(String)
    case pageNotFound

    var errorDescription: String? {
        switch self {
        case .notYetImplemented(let detail): "Not yet implemented: \(detail)"
        case .invalidURL(let url):           "'\(url)' is not a valid URL."
        case .pageNotFound:                  "The specified page could not be found."
        }
    }
}
