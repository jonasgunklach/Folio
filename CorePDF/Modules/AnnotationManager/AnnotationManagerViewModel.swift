// AnnotationManagerViewModel.swift
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
import AppKit
import PDFKit
import SwiftUI

/// Manages the active annotation settings and applies PDFKit annotations to pages.
/// Injected into views that host annotation tools.
@MainActor
@Observable
final class AnnotationManagerViewModel {

    // MARK: - Highlight Settings

    var highlightColor: NSColor
    var highlightOpacity: CGFloat

    // MARK: - Underline Settings

    var underlineColor: NSColor

    // MARK: - Strikethrough Settings

    var strikethroughColor: NSColor

    // MARK: - Freehand Settings

    var freehandColor: NSColor
    var freehandLineWidth: CGFloat

    // MARK: - Stamp Settings

    var availableStamps: [StampTemplate] = StampTemplate.defaults

    // MARK: - Init

    init() {
        let s = SettingsStore.shared
        highlightColor    = NSColor(s.highlightColor)
        highlightOpacity  = s.highlightOpacity
        underlineColor    = NSColor(s.underlineColor)
        strikethroughColor = NSColor(s.strikethroughColor)
        freehandColor     = NSColor(s.freehandColor)
        freehandLineWidth = s.freehandLineWidth
    }

    // MARK: - Annotation Application

    /// Adds a highlight annotation to the given selection on a PDF page.
    func addHighlight(selection: PDFSelection, in document: PDFDocument) {
        selection.pages.forEach { page in
            let bounds = selection.bounds(for: page)
            let annotation = PDFAnnotation(bounds: bounds, forType: .highlight, withProperties: nil)
            annotation.color = highlightColor.withAlphaComponent(highlightOpacity)
            page.addAnnotation(annotation)
        }
    }

    /// Adds a strikethrough annotation.
    func addStrikethrough(selection: PDFSelection, in document: PDFDocument) {
        selection.pages.forEach { page in
            let bounds = selection.bounds(for: page)
            let annotation = PDFAnnotation(bounds: bounds, forType: .strikeOut, withProperties: nil)
            annotation.color = NSColor.systemRed
            page.addAnnotation(annotation)
        }
    }

    /// Adds an underline annotation.
    func addUnderline(selection: PDFSelection, in document: PDFDocument) {
        selection.pages.forEach { page in
            let bounds = selection.bounds(for: page)
            let annotation = PDFAnnotation(bounds: bounds, forType: .underline, withProperties: nil)
            annotation.color = NSColor.systemBlue
            page.addAnnotation(annotation)
        }
    }

    /// Adds a freehand ink annotation with the given path.
    func addFreehandPath(_ path: NSBezierPath, on page: PDFPage) {
        let bounds = path.bounds.insetBy(dx: -freehandLineWidth, dy: -freehandLineWidth)
        let annotation = PDFAnnotation(bounds: bounds, forType: .ink, withProperties: nil)
        annotation.add(path)
        annotation.color = freehandColor
        annotation.border = PDFBorder()
        annotation.border?.lineWidth = freehandLineWidth
        page.addAnnotation(annotation)
    }

    /// Stamps the given page at a coordinate with a text label.
    func addStamp(_ template: StampTemplate, on page: PDFPage, at point: CGPoint) {
        let stampBounds = CGRect(
            x: point.x - 60,
            y: point.y - 20,
            width: 120,
            height: 40
        )
        let annotation = PDFAnnotation(bounds: stampBounds, forType: .stamp, withProperties: nil)
        annotation.setValue(template.label, forAnnotationKey: .contents)
        annotation.color = template.color
        page.addAnnotation(annotation)
    }

    /// Removes a specific annotation from its page.
    func removeAnnotation(_ annotation: PDFAnnotation, from page: PDFPage) {
        page.removeAnnotation(annotation)
    }
}

// MARK: - Stamp Template

struct StampTemplate: Identifiable {
    let id: UUID = UUID()
    let label: String
    let color: NSColor

    static let defaults: [StampTemplate] = [
        StampTemplate(label: "APPROVED",      color: .systemGreen),
        StampTemplate(label: "CONFIDENTIAL",  color: .systemRed),
        StampTemplate(label: "DRAFT",         color: .systemOrange),
        StampTemplate(label: "REVIEWED",      color: .systemBlue),
        StampTemplate(label: "VOID",          color: .systemGray),
    ]
}
