// ToolsSettingsPane.swift
// CorePDF
//
// MIT License
// Copyright (c) 2026 CorePDF Contributors

import SwiftUI

struct ToolsSettingsPane: View {

    @Environment(SettingsStore.self) private var settings

    private let configurableTools: [ActiveTool] = [
        .select, .highlight, .underline, .strikethrough, .text, .signature
    ]

    var body: some View {
        @Bindable var settings = settings
        Form {
            Section("Toolbar Tools") {
                Text("Choose which tools appear in the annotation toolbar.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(configurableTools) { tool in
                    let isOn = Binding<Bool>(
                        get: { settings.visibleTools.contains(tool) },
                        set: { newValue in
                            if newValue {
                                settings.visibleTools.insert(tool)
                            } else {
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
                        Spacer()
                        if let key = tool.keyboardShortcut {
                            Text(key)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(Color(NSColor.controlBackgroundColor))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 4)
                                                .strokeBorder(.separator, lineWidth: 0.5)
                                        )
                                )
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding(.vertical, 8)
    }
}
