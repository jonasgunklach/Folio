// AnnotationsSettingsPane.swift
// CorePDF
//
// MIT License
// Copyright (c) 2026 CorePDF Contributors

import SwiftUI

struct AnnotationsSettingsPane: View {

    @Environment(SettingsStore.self) private var settings

    var body: some View {
        @Bindable var settings = settings
        Form {
            Section("Highlight") {
                ColorPicker("Color", selection: $settings.highlightColor, supportsOpacity: false)
                HStack {
                    Text("Opacity")
                    Slider(value: $settings.highlightOpacity, in: 0.1...1.0, step: 0.05)
                    Text(String(format: "%.0f%%", settings.highlightOpacity * 100))
                        .font(.system(size: 12).monospacedDigit())
                        .frame(width: 36, alignment: .trailing)
                }
            }

            Section("Underline") {
                ColorPicker("Color", selection: $settings.underlineColor, supportsOpacity: false)
            }

            Section("Strikethrough") {
                ColorPicker("Color", selection: $settings.strikethroughColor, supportsOpacity: false)
            }

            Section("Freehand") {
                ColorPicker("Color", selection: $settings.freehandColor, supportsOpacity: false)
                HStack {
                    Text("Line width")
                    Slider(value: $settings.freehandLineWidth, in: 1.0...10.0, step: 0.5)
                    Text(String(format: "%.1f pt", settings.freehandLineWidth))
                        .font(.system(size: 12).monospacedDigit())
                        .frame(width: 44, alignment: .trailing)
                }
            }
        }
        .formStyle(.grouped)
        .padding(.vertical, 8)
    }
}
