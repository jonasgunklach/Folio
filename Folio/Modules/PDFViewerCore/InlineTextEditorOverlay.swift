// InlineTextEditorOverlay.swift
// Folio
//
// MIT License
// Copyright (c) 2026 Folio Contributors
//
// NSViewRepresentable wrapper around NSTextField used for the inline PDF text
// editor.  Placed as a SwiftUI overlay exactly over the tapped text line.
// Commits on Return/Tab, cancels on Escape.

import SwiftUI
import AppKit

/// Auto-focused NSTextField overlay for in-place PDF text editing.
///
/// Coordinate placement is handled by the caller (PDFViewerView) which converts
/// the PDF page rect to SwiftUI view coordinates and applies `.frame` + `.offset`.
struct InlineTextEditorOverlay: NSViewRepresentable {

    @Binding var text: String
    /// Font size already pre-scaled by the current PDF zoom factor (screen points).
    let fontSize: CGFloat
    /// PostScript font name of the original text (e.g. "Helvetica-Bold").
    let fontName: String
    /// Original text colour. Automatically replaced with `.labelColor` when the
    /// colour is too light to be readable on the white editor background.
    let textColor: NSColor
    /// True when the tapped selection spans multiple lines (paragraph). Enables
    /// text wrapping so the editor fills the full bounding box.
    let isMultiLine: Bool
    let onCommit: () -> Void
    let onCancel: () -> Void

    func makeNSView(context: Context) -> NSTextField {
        let tf = NSTextField()
        tf.delegate = context.coordinator
        tf.stringValue = text
        tf.isBordered = false
        tf.isEditable = true
        tf.isSelectable = true
        tf.backgroundColor = .clear
        tf.drawsBackground = false
        tf.focusRingType = .none
        tf.textColor = readableColor
        tf.font = resolvedFont(size: fontSize)
        tf.cell?.wraps = isMultiLine
        tf.cell?.isScrollable = !isMultiLine
        return tf
    }

    func updateNSView(_ tf: NSTextField, context: Context) {
        if tf.stringValue != text { tf.stringValue = text }
        tf.font = resolvedFont(size: fontSize)
        tf.textColor = readableColor
        tf.cell?.wraps = isMultiLine
        tf.cell?.isScrollable = !isMultiLine

        // Auto-focus exactly once, deferred to the next run loop so the view
        // is guaranteed to be in the window hierarchy before we make it first responder.
        guard !context.coordinator.hasFocused else { return }
        context.coordinator.hasFocused = true
        DispatchQueue.main.async {
            guard let window = tf.window else { return }
            window.makeFirstResponder(tf)
            tf.currentEditor()?.selectAll(nil)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    // MARK: - Coordinator

    final class Coordinator: NSObject, NSTextFieldDelegate {

        var parent: InlineTextEditorOverlay
        var hasFocused = false

        init(_ parent: InlineTextEditorOverlay) { self.parent = parent }

        func controlTextDidChange(_ obj: Notification) {
            guard let tf = obj.object as? NSTextField else { return }
            parent.text = tf.stringValue
        }

        func control(_ control: NSControl, textView: NSTextView,
                     doCommandBy selector: Selector) -> Bool {
            switch selector {
            case #selector(NSResponder.insertNewline(_:)),
                 #selector(NSResponder.insertTab(_:)):
                parent.onCommit()
                return true
            case #selector(NSResponder.cancelOperation(_:)):
                parent.onCancel()
                return true
            default:
                return false
            }
        }
    }

    // MARK: - Helpers

    /// Original colour, or `.labelColor` if it's too light to read on white.
    private var readableColor: NSColor {
        var white: CGFloat = 0
        (textColor.usingColorSpace(.deviceGray) ?? textColor).getWhite(&white, alpha: nil)
        return white > 0.75 ? .labelColor : textColor
    }

    private func resolvedFont(size: CGFloat) -> NSFont {
        // Strip PDF subset prefix like "ABCDEF+" before looking up the font.
        let base: String
        if let plusIdx = fontName.firstIndex(of: "+") {
            base = String(fontName[fontName.index(after: plusIdx)...])
        } else {
            base = fontName
        }
        return NSFont(name: base, size: max(size, 8)) ?? NSFont.systemFont(ofSize: max(size, 8))
    }
}
