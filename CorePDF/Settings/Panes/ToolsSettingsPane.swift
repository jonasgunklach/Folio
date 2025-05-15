// ToolsSettingsPane.swift
// CorePDF
//
// MIT License
// Copyright (c) 2026 CorePDF Contributors

import SwiftUI

struct ToolsSettingsPane: View {

    @Environment(SettingsStore.self) private var settings

    /// Tools that can be toggled in the toolbar (all except non-primary ones like stamp/signature).
    private let configurableTools: [ActiveTool] = [
        .select, .highlight, .underline, .strikethrough, .freehand, .text
    ]

    var body: some View {
        @Bindable var settings = settings
        Form {
            Section {
                Text("Choose which tools appear in the annotation toolbar. At least one tool must remain visible.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Toolbar Tools") {
                ForEach(configurableTools) { tool in
                    let isOn = Binding<Bool>(
                        get: { settings.visibleTools.contains(tool) },
                        set: { newValue in
                            if newValue {
                                settings.visibleTools.insert(tool)
                            } else {
                                // Always keep at least one tool visible
                                guard settings.visibleTools.count > 1 else { return }
                                settings.visibleTools.remove(tool)
                            }
                        }
                    )
                    HStack(spacing: 10) {
                        Image(systemName: tool.symbolName)
                            .symbolRenderingMode(.multicolor)
                            .frame(width: 22)
                        Toggle(tool.rawValue, isOn: isOn)
                    }
                }
            }

            Section("Keyboard Shortcuts") {
                LabeledContent("Select",        value: "E")
                LabeledContent("Highlight",     value: "H")
                LabeledContent("Underline",     value: "U")
                LabeledContent("Strikethrough", value: "K")
                LabeledContent("Freehand",      value: "F")
                LabeledContent("Text Box",      value: "T")
            }
        }
        .formStyle(.grouped)
        .padding(.vertical, 8)
    }
}
