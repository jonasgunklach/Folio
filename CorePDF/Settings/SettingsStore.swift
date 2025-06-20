// SettingsStore.swift
// CorePDF
//
// MIT License
// Copyright (c) 2026 CorePDF Contributors

import AppKit
import SwiftUI

// MARK: - Appearance Mode

enum AppearanceMode: String, CaseIterable, Identifiable {
    case system = "System"
    case light  = "Light"
    case dark   = "Dark"

    var id: String { rawValue }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light:  .light
        case .dark:   .dark
        }
    }

    var previewSystemImage: String {
        switch self {
        case .system: "circle.lefthalf.filled"
        case .light:  "sun.max.fill"
        case .dark:   "moon.stars.fill"
        }
    }
}

// MARK: - Tab Bar Style

enum TabBarStyle: String, CaseIterable, Identifiable {
    /// Pills embedded in the toolbar's principal slot (compact).
    case toolbar = "In Toolbar"
    /// Dedicated tab strip row pinned between the toolbar and the document.
    case bar     = "Tab Bar"

    var id: String { rawValue }

    var symbolName: String {
        switch self {
        case .toolbar: "square.grid.3x1.below.line.grid.1x2"
        case .bar:     "menubar.rectangle"
        }
    }
}

// MARK: - Settings Store

/// Persistent application preferences, backed by UserDefaults.
/// Singleton; access via `SettingsStore.shared`. Injected as `@Environment` in both scenes.
@MainActor
@Observable
final class SettingsStore {

    static let shared = SettingsStore()
    private init() { load() }

    // MARK: General

    var appearanceMode: AppearanceMode = .system {
        didSet { save(appearanceMode.rawValue, key: Keys.appearanceMode) }
    }

    var defaultReadingMode: ReadingMode = .default {
        didSet { save(defaultReadingMode.rawValue, key: Keys.defaultReadingMode) }
    }

    var showSidebarByDefault: Bool = true {
        didSet { save(showSidebarByDefault, key: Keys.showSidebarByDefault) }
    }

    var restoreDocumentsOnLaunch: Bool = false {
        didSet { save(restoreDocumentsOnLaunch, key: Keys.restoreDocumentsOnLaunch) }
    }

    var tabBarStyle: TabBarStyle = .toolbar {
        didSet { save(tabBarStyle.rawValue, key: Keys.tabBarStyle) }
    }

    // MARK: Display

    var defaultZoom: Double = 1.0 {
        didSet { save(defaultZoom, key: Keys.defaultZoom) }
    }

    var defaultViewMode: ViewMode = .scroll {
        didSet { save(defaultViewMode.rawValue, key: Keys.defaultViewMode) }
    }

    // MARK: Annotations

    var highlightColor: Color = .yellow {
        didSet { saveColor(highlightColor, key: Keys.highlightColor) }
    }

    var highlightOpacity: Double = 0.4 {
        didSet { save(highlightOpacity, key: Keys.highlightOpacity) }
    }

    var underlineColor: Color = .blue {
        didSet { saveColor(underlineColor, key: Keys.underlineColor) }
    }

    var strikethroughColor: Color = .red {
        didSet { saveColor(strikethroughColor, key: Keys.strikethroughColor) }
    }

    // MARK: Tools

    /// The annotation tools visible in the toolbar segmented picker.
    var visibleTools: Set<ActiveTool> = [.select, .highlight, .underline, .strikethrough, .text, .signature] {
        didSet {
            let raw = visibleTools.map(\.rawValue)
            UserDefaults.standard.set(raw, forKey: Keys.visibleTools)
        }
    }

    // MARK: - Private Persistence

    private func load() {
        let d = UserDefaults.standard
        appearanceMode       = AppearanceMode(rawValue: d.string(forKey: Keys.appearanceMode) ?? "") ?? .system
        defaultReadingMode   = ReadingMode(rawValue: d.string(forKey: Keys.defaultReadingMode) ?? "") ?? .default
        showSidebarByDefault = d.object(forKey: Keys.showSidebarByDefault) as? Bool ?? true
        restoreDocumentsOnLaunch = d.bool(forKey: Keys.restoreDocumentsOnLaunch)
        tabBarStyle          = TabBarStyle(rawValue: d.string(forKey: Keys.tabBarStyle) ?? "") ?? .toolbar
        if d.object(forKey: Keys.defaultZoom) != nil { defaultZoom = d.double(forKey: Keys.defaultZoom) }
        defaultViewMode      = ViewMode(rawValue: d.string(forKey: Keys.defaultViewMode) ?? "") ?? .scroll
        highlightColor       = loadColor(key: Keys.highlightColor) ?? .yellow
        if d.object(forKey: Keys.highlightOpacity) != nil { highlightOpacity = d.double(forKey: Keys.highlightOpacity) }
        underlineColor       = loadColor(key: Keys.underlineColor) ?? .blue
        strikethroughColor   = loadColor(key: Keys.strikethroughColor) ?? .red
        if let raw = d.stringArray(forKey: Keys.visibleTools) {
            let tools = raw.compactMap(ActiveTool.init(rawValue:))
            if !tools.isEmpty { visibleTools = Set(tools) }
        }
    }

    private func save(_ value: some Any, key: String) {
        UserDefaults.standard.set(value, forKey: key)
    }

    private func saveColor(_ color: Color, key: String) {
        guard let data = try? NSKeyedArchiver.archivedData(
            withRootObject: NSColor(color), requiringSecureCoding: false)
        else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    private func loadColor(key: String) -> Color? {
        guard let data = UserDefaults.standard.data(forKey: key),
              let nsColor = try? NSKeyedUnarchiver.unarchivedObject(
                ofClass: NSColor.self, from: data)
        else { return nil }
        return Color(nsColor)
    }

    private enum Keys {
        static let appearanceMode           = "settings.appearanceMode"
        static let defaultReadingMode       = "settings.defaultReadingMode"
        static let showSidebarByDefault     = "settings.showSidebarByDefault"
        static let restoreDocumentsOnLaunch = "settings.restoreDocumentsOnLaunch"
        static let tabBarStyle              = "settings.tabBarStyle"
        static let defaultZoom              = "settings.defaultZoom"
        static let defaultViewMode          = "settings.defaultViewMode"
        static let highlightColor           = "settings.highlightColor"
        static let highlightOpacity         = "settings.highlightOpacity"
        static let underlineColor           = "settings.underlineColor"
        static let strikethroughColor       = "settings.strikethroughColor"
        static let visibleTools             = "settings.visibleTools"
    }
}
