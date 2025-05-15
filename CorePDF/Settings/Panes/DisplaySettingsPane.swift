// DisplaySettingsPane.swift
// CorePDF
//
// MIT License
// Copyright (c) 2026 CorePDF Contributors

import SwiftUI

struct DisplaySettingsPane: View {

    @Environment(SettingsStore.self) private var settings

    var body: some View {
        @Bindable var settings = settings
        Form {
            Section("Default Layout") {
                Picker("Default view", selection: $settings.defaultViewMode) {
                    ForEach(ViewMode.allCases) { mode in
                        Label(mode.rawValue, systemImage: mode.symbolName).tag(mode)
                    }
                }
                .pickerStyle(.radioGroup)
            }

            Section("Default Zoom") {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Slider(value: $settings.defaultZoom, in: 0.25...4.0, step: 0.25)
                        Text(String(format: "%.0f%%", settings.defaultZoom * 100))
                            .font(.system(size: 12, weight: .medium).monospacedDigit())
                            .frame(width: 44, alignment: .trailing)
                    }
                    Text("Applied when opening a new document")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .padding(.vertical, 8)
    }
}
