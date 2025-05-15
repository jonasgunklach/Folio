// FormHandlerViewModel.swift
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

/// Detects and manages interactive PDF form fields (text fields, checkboxes, radio buttons).
/// PDFKit exposes AcroForm widgets via `PDFAnnotationSubtype.widget`.
@MainActor
@Observable
final class FormHandlerViewModel {

    // MARK: - Detected Fields

    var formFields: [PDFFormField] = []

    // MARK: - Field Discovery

    func detectFields(in document: PDFDocument) {
        var detected: [PDFFormField] = []

        for pageIndex in 0..<document.pageCount {
            guard let page = document.page(at: pageIndex) else { continue }

            let widgets = page.annotations.filter { annotation in
                annotation.type == "Widget"
            }

            for widget in widgets {
                let field = PDFFormField(annotation: widget, pageIndex: pageIndex)
                detected.append(field)
            }
        }

        formFields = detected
    }

    // MARK: - Field Interaction

    func setValue(_ value: String, for field: PDFFormField) {
        field.annotation.setValue(value, forAnnotationKey: .widgetValue)
        if let index = formFields.firstIndex(where: { $0.id == field.id }) {
            formFields[index].currentValue = value
        }
    }

    func toggleCheckbox(_ field: PDFFormField) {
        let isOn = field.currentValue == "Yes"
        let newValue = isOn ? "Off" : "Yes"
        field.annotation.setValue(newValue, forAnnotationKey: .widgetValue)
        if let index = formFields.firstIndex(where: { $0.id == field.id }) {
            formFields[index].currentValue = newValue
        }
    }
}

// MARK: - Form Field Model

@Observable
final class PDFFormField: Identifiable {

    let id: UUID = UUID()
    let annotation: PDFAnnotation
    let pageIndex: Int
    var currentValue: String

    var fieldType: FormFieldType {
        guard let typeValue = annotation.value(forAnnotationKey: .widgetFieldType) as? String else {
            return .unknown
        }
        return FormFieldType(rawValue: typeValue) ?? .unknown
    }

    var fieldName: String {
        annotation.fieldName ?? "Unnamed Field"
    }

    init(annotation: PDFAnnotation, pageIndex: Int) {
        self.annotation = annotation
        self.pageIndex = pageIndex
        self.currentValue = annotation.value(forAnnotationKey: .widgetValue) as? String ?? ""
    }
}

// MARK: - Field Type

enum FormFieldType: String {
    case text       = "Tx"
    case button     = "Btn"
    case choice     = "Ch"
    case signature  = "Sig"
    case unknown    = ""
}
