// SettingsView.swift
// CorePDF
//
// MIT License
// Copyright (c) 2026 CorePDF Contributors

import SwiftUI

// MARK: - Settings Pane Enum

enum SettingsPane: String, CaseIterable, Identifiable {
    case general     = "General"
    case display     = "Display"
    case annotations = "Annotations"
    case tools       = "Tools"

    var id: String { rawValue }

    var symbolName: String {
        switch self {
        case .general:     "gearshape"
        case .display:     "rectangle.on.rectangle"
        case .annotations: "pencil.and.outline"
        case .tools:       "wrench.and.screwdriver"
        }
    }
}

// MARK: - Settings Window Root

struct SettingsView: View {

    @State private var selection: SettingsPane = .general

    var body: some View {
        NavigationSplitView(columnVisibility: .constant(.all)) {
            List(SettingsPane.allCases, selection: $selection) { pane in
                Label(pane.rawValue, systemImage: pane.symbolName)
                    .tag(pane)
            }
            .navigationSplitViewColumnWidth(min: 170, ideal: 190, max: 210)
            .navigationTitle("Settings")
        } detail: {
            Group {
                switch selection {
                case .general:     GeneralSettingsPane()
                case .display:     DisplaySettingsPane()
                case .annotations: AnnotationsSettingsPane()
                case .tools:       ToolsSettingsPane()
                }
            }
            .navigationTitle(selection.rawValue)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .frame(minWidth: 620, idealWidth: 680, minHeight: 420, idealHeight: 480)
    }
}
