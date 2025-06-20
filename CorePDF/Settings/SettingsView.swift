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
        TabView(selection: $selection) {
            ForEach(SettingsPane.allCases) { pane in
                settingsContent(for: pane)
                    .tabItem {
                        Label(pane.rawValue, systemImage: pane.symbolName)
                    }
                    .tag(pane)
            }
        }
        .frame(minWidth: 480, idealWidth: 520, minHeight: 360, idealHeight: 400)
    }

    @ViewBuilder
    private func settingsContent(for pane: SettingsPane) -> some View {
        switch pane {
        case .general:     GeneralSettingsPane()
        case .display:     DisplaySettingsPane()
        case .annotations: AnnotationsSettingsPane()
        case .tools:       ToolsSettingsPane()
        }
    }
}
