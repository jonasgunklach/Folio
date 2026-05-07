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

// MARK: - Shape type

/// The kind of shape the shape tool will draw.
enum ShapeType: String, CaseIterable, Identifiable {
    case rectangle = "Rectangle"
    case ellipse   = "Ellipse"
    case line      = "Line"
    var id: String { rawValue }

    var symbolName: String {
        switch self {
        case .rectangle: "rectangle"
        case .ellipse:   "oval"
        case .line:      "line.diagonal"
        }
    }
}

// MARK: - Markup sub-tool

/// Which markup variant is active under the unified `.markup` tool.
enum MarkupSubtool: String, CaseIterable, Identifiable {
    case highlight      = "Highlight"
    case underline      = "Underline"
    case strikethrough  = "Strikethrough"
    var id: String { rawValue }

    var symbolName: String {
        switch self {
        case .highlight:     "a.square.fill"
        case .underline:     "underline"
        case .strikethrough: "strikethrough"
        }
    }
}

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

    // MARK: - Markup sub-tool

    var markupSubtool: MarkupSubtool = .highlight

    // MARK: - Text Box Settings

    var textBoxFont: NSFont = .systemFont(ofSize: 16)
    var textBoxColor: NSColor = .black

    // MARK: - Shape Settings

    var shapeType: ShapeType = .rectangle
    var shapeStrokeColor: NSColor = .systemRed {
        didSet { applyShapeStyleToSelectedAnnotation() }
    }
    var shapeFillColor: NSColor = .clear {
        didSet { applyShapeStyleToSelectedAnnotation() }
    }
    var shapeLineWidth: CGFloat = 2 {
        didSet { applyShapeStyleToSelectedAnnotation() }
    }

    // MARK: - Selected annotation (shape editing via palette in select mode)

    /// The shape annotation currently selected for resizing/editing.
    /// Set by `PDFKitView.Coordinator`; cleared on deselect or tool change.
    weak var selectedAnnotation: PDFAnnotation? = nil

    /// True while we're copying annotation properties INTO the viewModel so
    /// that `didSet` observers don't write them back to the annotation.
    private var isLoadingFromAnnotation = false

    /// Copies the annotation's current visual properties into the palette
    /// settings and records it as the selection target.
    func selectAnnotation(_ ann: PDFAnnotation) {
        isLoadingFromAnnotation = true
        selectedAnnotation = ann
        shapeStrokeColor = ann.color
        shapeFillColor   = ann.interiorColor ?? .clear
        if let border = ann.border { shapeLineWidth = border.lineWidth > 0 ? border.lineWidth : 2 }
        // Detect shape type from PDFKit subtype string or FolioType tag
        let folioType = ann.value(forAnnotationKey: PDFAnnotationKey(rawValue: "/FolioType")) as? String
        if folioType == "line" {
            shapeType = .line
        } else {
            switch ann.type {
            case "Square":  shapeType = .rectangle
            case "Circle":  shapeType = .ellipse
            case "Line":    shapeType = .line
            default:        break
            }
        }
        isLoadingFromAnnotation = false
    }

    func deselectAnnotation() {
        selectedAnnotation = nil
    }

    private func applyShapeStyleToSelectedAnnotation() {
        guard !isLoadingFromAnnotation, let ann = selectedAnnotation else { return }
        ann.color = shapeStrokeColor
        ann.interiorColor = shapeFillColor == .clear ? nil : shapeFillColor
        let border = PDFBorder()
        border.lineWidth = shapeLineWidth
        border.style = .solid
        ann.border = border
    }

    // MARK: - Stamp Settings

    var availableStamps: [StampTemplate] = StampTemplate.defaults
    var selectedStamp: StampTemplate? = StampTemplate.defaults.first

    // MARK: - Init

    init() {
        let s = SettingsStore.shared
        highlightColor    = NSColor(s.highlightColor)
        highlightOpacity  = s.highlightOpacity
        underlineColor    = NSColor(s.underlineColor)
        strikethroughColor = NSColor(s.strikethroughColor)
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

    /// Stamps the given page at a coordinate with a text label.
    func addStamp(_ template: StampTemplate, on page: PDFPage, at point: CGPoint) {
        let stampBounds = CGRect(
            x: point.x - 60,
            y: point.y - 20,
            width: 120,
            height: 40
        )
        let annotation = PDFTextStampAnnotation(
            label:  template.label,
            color:  template.color,
            bounds: stampBounds
        )
        page.addAnnotation(annotation)
    }

    /// Adds a freeText annotation (editable text box) at the given page point.
    @discardableResult
    func addTextBox(at point: CGPoint, on page: PDFPage) -> PDFAnnotation {
        let defaultWidth: CGFloat  = 200
        let defaultHeight: CGFloat = 40
        let bounds = CGRect(x: point.x - defaultWidth / 2,
                            y: point.y - defaultHeight / 2,
                            width: defaultWidth,
                            height: defaultHeight)
        let ann = PDFAnnotation(bounds: bounds, forType: .freeText, withProperties: nil)
        ann.contents  = "Text"
        ann.font      = textBoxFont
        ann.fontColor = textBoxColor
        ann.color     = .clear
        ann.isReadOnly = false
        ann.shouldDisplay = true
        ann.shouldPrint   = true
        // Tag so double-click knows this is an editable text box
        ann.setValue("textbox" as NSString,
                     forAnnotationKey: PDFAnnotationKey(rawValue: "/FolioType"))
        let border = PDFBorder()
        border.lineWidth = 0
        ann.border = border
        page.addAnnotation(ann)
        return ann
    }

    /// Adds a shape annotation (rectangle, ellipse, or line) to a page.
    /// `rect` is in PDF coordinates (origin bottom-left).
    @discardableResult
    func addShape(type: ShapeType, rect: CGRect, on page: PDFPage) -> PDFAnnotation {
        let subtype: PDFAnnotationSubtype
        switch type {
        case .rectangle: subtype = .square
        case .ellipse:   subtype = .circle
        case .line:      subtype = .line
        }
        let ann = PDFAnnotation(bounds: rect, forType: subtype, withProperties: nil)
        ann.color = shapeStrokeColor
        if shapeFillColor != .clear {
            ann.interiorColor = shapeFillColor
        }
        let border = PDFBorder()
        border.lineWidth = shapeLineWidth
        border.style = .solid
        ann.border = border
        if type == .line {
            ann.startLineStyle  = .none
            ann.endLineStyle    = .none
            ann.startPoint      = CGPoint(x: rect.minX, y: rect.midY)
            ann.endPoint        = CGPoint(x: rect.maxX, y: rect.midY)
        }
        ann.isReadOnly    = false
        ann.shouldDisplay = true
        ann.shouldPrint   = true
        page.addAnnotation(ann)
        return ann
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
