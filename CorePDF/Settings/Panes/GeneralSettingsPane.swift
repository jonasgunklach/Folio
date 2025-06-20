// GeneralSettingsPane.swift
// CorePDF
//
// MIT License
// Copyright (c) 2026 CorePDF Contributors

import SwiftUI

struct GeneralSettingsPane: View {

    @Environment(SettingsStore.self) private var settings

    var body: some View {
        @Bindable var settings = settings
        Form {
            // ── Appearance ────────────────────────────────────────────
            Section("Appearance") {
                AppearancePicker(selection: $settings.appearanceMode)
                Divider().padding(.vertical, 4)
                TabBarStylePicker(selection: $settings.tabBarStyle)
            }

            // ── On Launch ────────────────────────────────────────────
            Section("On Launch") {
                Toggle("Restore open documents on launch", isOn: $settings.restoreDocumentsOnLaunch)

                Picker("Default reading mode", selection: $settings.defaultReadingMode) {
                    ForEach(ReadingMode.allCases) { mode in
                        Label(mode.rawValue, systemImage: mode.symbolName).tag(mode)
                    }
                }

                Toggle("Show sidebar by default", isOn: $settings.showSidebarByDefault)
            }
        }
        .formStyle(.grouped)
        .padding(.vertical, 8)
    }
}

// MARK: - Appearance Picker (Xcode-style cards)

private struct AppearancePicker: View {

    @Binding var selection: AppearanceMode

    var body: some View {
        HStack(spacing: 16) {
            ForEach(AppearanceMode.allCases) { mode in
                AppearanceCard(mode: mode, isSelected: selection == mode)
                    .onTapGesture { selection = mode }
            }
        }
        .padding(.vertical, 4)
    }
}

private struct AppearanceCard: View {

    let mode: AppearanceMode
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 6) {
            // Mini window preview
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(cardBackground)
                    .frame(width: 88, height: 60)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(isSelected ? Color.accentColor : Color.gray.opacity(0.3),
                                          lineWidth: isSelected ? 2 : 1)
                    )
                    .shadow(color: .black.opacity(0.12), radius: 4, y: 2)

                VStack(spacing: 4) {
                    // Fake toolbar strip
                    Capsule()
                        .fill(toolbarColor)
                        .frame(width: 60, height: 8)
                    // Fake content lines
                    VStack(spacing: 3) {
                        Capsule().fill(contentLineColor).frame(width: 50, height: 4)
                        Capsule().fill(contentLineColor).frame(width: 40, height: 4)
                    }
                }

                // Checkmark overlay when selected
                if isSelected {
                    VStack {
                        HStack {
                            Spacer()
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.white, Color.accentColor)
                                .font(.system(size: 14))
                                .offset(x: 6, y: -6)
                        }
                        Spacer()
                    }
                }
            }
            .frame(width: 88, height: 60)

            Text(mode.rawValue)
                .font(.caption)
                .foregroundStyle(isSelected ? .primary : .secondary)
        }
        .contentShape(Rectangle())
    }

    private var cardBackground: Color {
        switch mode {
        case .system: Color(NSColor.windowBackgroundColor)
        case .light:  Color(red: 0.95, green: 0.95, blue: 0.97)
        case .dark:   Color(red: 0.17, green: 0.17, blue: 0.19)
        }
    }

    private var toolbarColor: Color {
        switch mode {
        case .system: Color(NSColor.controlBackgroundColor)
        case .light:  Color(red: 0.88, green: 0.88, blue: 0.90)
        case .dark:   Color(red: 0.26, green: 0.26, blue: 0.28)
        }
    }

    private var contentLineColor: Color {
        switch mode {
        case .system: Color(NSColor.secondaryLabelColor)
        case .light:  Color.gray.opacity(0.4)
        case .dark:   Color.white.opacity(0.25)
        }
    }
}

// MARK: - Tab Bar Style Picker (card-style, mirrors AppearancePicker)

private struct TabBarStylePicker: View {

    @Binding var selection: TabBarStyle

    var body: some View {
        HStack(spacing: 16) {
            ForEach(TabBarStyle.allCases) { style in
                TabBarStyleCard(style: style, isSelected: selection == style)
                    .onTapGesture { selection = style }
            }
        }
        .padding(.vertical, 4)
    }
}

private struct TabBarStyleCard: View {

    let style: TabBarStyle
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(NSColor.windowBackgroundColor))
                    .frame(width: 88, height: 60)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(isSelected ? Color.accentColor : Color.gray.opacity(0.3),
                                          lineWidth: isSelected ? 2 : 1)
                    )
                    .shadow(color: .black.opacity(0.12), radius: 4, y: 2)

                VStack(spacing: 0) {
                    // Toolbar strip
                    ZStack {
                        Color(NSColor.controlBackgroundColor)
                        if style == .toolbar {
                            // Tab pills sit inside the toolbar
                            HStack(spacing: 3) {
                                Capsule()
                                    .fill(Color.accentColor.opacity(0.7))
                                    .frame(width: 18, height: 5)
                                Capsule()
                                    .fill(Color.gray.opacity(0.35))
                                    .frame(width: 14, height: 5)
                                Capsule()
                                    .fill(Color.gray.opacity(0.35))
                                    .frame(width: 14, height: 5)
                            }
                        }
                    }
                    .frame(height: 16)

                    // Dedicated tab bar strip (only in .bar style)
                    if style == .bar {
                        ZStack {
                            Color(NSColor.windowBackgroundColor).opacity(0.85)
                            HStack(spacing: 3) {
                                Capsule()
                                    .fill(Color.accentColor.opacity(0.7))
                                    .frame(width: 18, height: 4)
                                Capsule()
                                    .fill(Color.gray.opacity(0.35))
                                    .frame(width: 14, height: 4)
                            }
                        }
                        .frame(height: 10)
                    }

                    // Content area
                    VStack(spacing: 3) {
                        Capsule()
                            .fill(Color(NSColor.secondaryLabelColor).opacity(0.35))
                            .frame(width: 50, height: 3)
                        Capsule()
                            .fill(Color(NSColor.secondaryLabelColor).opacity(0.35))
                            .frame(width: 40, height: 3)
                    }
                    .frame(maxHeight: .infinity)
                }
                .clipShape(RoundedRectangle(cornerRadius: 8))

                if isSelected {
                    VStack {
                        HStack {
                            Spacer()
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.white, Color.accentColor)
                                .font(.system(size: 14))
                                .offset(x: 6, y: -6)
                        }
                        Spacer()
                    }
                }
            }
            .frame(width: 88, height: 60)

            Text(style.rawValue)
                .font(.caption)
                .foregroundStyle(isSelected ? .primary : .secondary)
        }
        .contentShape(Rectangle())
    }
}
