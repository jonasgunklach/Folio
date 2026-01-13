// ActiveTool.swift
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

enum ActiveTool: String, CaseIterable, Identifiable {
    case select         = "Select"
    case highlight      = "Highlight"
    case strikethrough  = "Strikethrough"
    case underline      = "Underline"
    case text           = "Comment"
    case stamp          = "Stamp"
    case signature      = "Signature"
    case audioNote      = "Audio Note"

    var id: String { rawValue }

    var symbolName: String {
        switch self {
        case .select:           "cursorarrow"
        case .highlight:        "a.square.fill"
        case .strikethrough:    "strikethrough"
        case .underline:        "underline"
        case .text:             "bubble.left.fill"
        case .stamp:            "stamp.fill"
        case .signature:        "signature"
        case .audioNote:        "mic.fill"
        }
    }

    /// Human-readable keyboard shortcut key for display in Settings.
    var keyboardShortcut: String? {
        switch self {
        case .select:        "E"
        case .highlight:     "H"
        case .underline:     "U"
        case .strikethrough: "K"
        case .text:          "C"
        case .signature:     "G"
        default:             nil
        }
    }

    /// Tools shown in the segmented picker in the toolbar.
    /// Driven by `SettingsStore.shared.visibleTools`; falls back to a default set
    /// when called before the store has loaded (e.g., enum init).
    var isPrimaryTool: Bool {
        SettingsStore.shared.visibleTools.contains(self)
    }

    var isAnnotationTool: Bool { self != .select }
}
