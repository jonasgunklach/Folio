// AnnotationToolPaletteView.swift
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

import SwiftUI

/// Floating context-sensitive palette that appears at the bottom of the PDF canvas
/// when an annotation tool is active. Provides quick-access settings for the
/// active tool (color, opacity, stroke width).
struct AnnotationToolPaletteView: View {

    @Bindable var viewModel: AnnotationManagerViewModel
    var activeTool: ActiveTool

    var body: some View {
        HStack(spacing: 12) {
            switch activeTool {
            case .markup:
                MarkupPaletteControls(viewModel: viewModel)
            case .highlight:
                HighlightPaletteControls(viewModel: viewModel)
            case .underline:
                UnderlinePaletteControls(viewModel: viewModel)
            case .strikethrough:
                StrikethroughPaletteControls(viewModel: viewModel)
            case .stamp:
                StampPaletteControls(viewModel: viewModel)
            case .text:
                Label("Click anywhere to place a comment", systemImage: "bubble.left.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case .addText:
                AddTextPaletteControls(viewModel: viewModel)
            case .shape:
                ShapePaletteControls(viewModel: viewModel)
            case .signature:
                Label("Click anywhere to place your signature", systemImage: "signature")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            default:
                EmptyView()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.14), radius: 10, y: 3)
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(.separator.opacity(0.4), lineWidth: 0.5)
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

// MARK: - Markup Controls (unified highlight / underline / strikethrough)

struct MarkupPaletteControls: View {
    @Bindable var viewModel: AnnotationManagerViewModel
    private let presetColors: [NSColor] = [
        .systemYellow, .systemGreen, .systemBlue, .systemPink, .systemOrange, .black
    ]

    var body: some View {
        HStack(spacing: 10) {
            // Sub-tool selector
            HStack(spacing: 4) {
                ForEach(MarkupSubtool.allCases) { sub in
                    Button {
                        viewModel.markupSubtool = sub
                    } label: {
                        Image(systemName: sub.symbolName)
                            .font(.system(size: 15, weight: .medium))
                            .frame(width: 26, height: 26)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(viewModel.markupSubtool == sub
                                ? Color.accentColor.opacity(0.18) : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .help(sub.rawValue)
                }
            }

            Divider().frame(height: 18)

            // Color swatches for the active sub-tool
            ForEach(presetColors, id: \.self) { color in
                colorSwatch(color, selected: activeColor == color) {
                    setActiveColor(color)
                }
            }

            // Opacity slider for highlight
            if viewModel.markupSubtool == .highlight {
                Divider().frame(height: 18)
                Text("Opacity").font(.caption).foregroundStyle(.secondary)
                Slider(value: $viewModel.highlightOpacity, in: 0.1...1.0)
                    .frame(width: 80)
            }
        }
    }

    private var activeColor: NSColor {
        switch viewModel.markupSubtool {
        case .highlight:     viewModel.highlightColor
        case .underline:     viewModel.underlineColor
        case .strikethrough: viewModel.strikethroughColor
        }
    }
    private func setActiveColor(_ c: NSColor) {
        switch viewModel.markupSubtool {
        case .highlight:     viewModel.highlightColor = c
        case .underline:     viewModel.underlineColor = c
        case .strikethrough: viewModel.strikethroughColor = c
        }
    }
}

// MARK: - Highlight Controls

struct HighlightPaletteControls: View {

    @Bindable var viewModel: AnnotationManagerViewModel
    private let presetColors: [NSColor] = [
        .systemYellow, .systemGreen, .systemBlue,
        .systemPink, .systemOrange, .systemPurple
    ]

    var body: some View {
        HStack(spacing: 8) {
            Text("Color")
                .font(.caption)
                .foregroundStyle(.secondary)

            ForEach(presetColors, id: \.self) { color in
                colorSwatch(color, selected: viewModel.highlightColor == color) {
                    viewModel.highlightColor = color
                }
            }

            Divider().frame(height: 18)

            Text("Opacity")
                .font(.caption)
                .foregroundStyle(.secondary)

            Slider(value: $viewModel.highlightOpacity, in: 0.1...1.0)
            .frame(width: 80)
        }
    }
}

// MARK: - Underline Controls

struct UnderlinePaletteControls: View {

    @Bindable var viewModel: AnnotationManagerViewModel
    private let presetColors: [NSColor] = [
        .systemBlue, .systemRed, .systemGreen,
        .systemOrange, .systemPurple, .black
    ]

    var body: some View {
        HStack(spacing: 8) {
            Text("Color")
                .font(.caption)
                .foregroundStyle(.secondary)

            ForEach(presetColors, id: \.self) { color in
                colorSwatch(color, selected: viewModel.underlineColor == color) {
                    viewModel.underlineColor = color
                }
            }
        }
    }
}

// MARK: - Strikethrough Controls

struct StrikethroughPaletteControls: View {

    @Bindable var viewModel: AnnotationManagerViewModel
    private let presetColors: [NSColor] = [
        .systemRed, .systemOrange, .systemBlue,
        .systemGreen, .systemPurple, .black
    ]

    var body: some View {
        HStack(spacing: 8) {
            Text("Color")
                .font(.caption)
                .foregroundStyle(.secondary)

            ForEach(presetColors, id: \.self) { color in
                colorSwatch(color, selected: viewModel.strikethroughColor == color) {
                    viewModel.strikethroughColor = color
                }
            }
        }
    }
}

// MARK: - Shared swatch helpers

private func colorSwatch(_ color: NSColor, selected: Bool, action: @escaping () -> Void) -> some View {
    Circle()
        .fill(Color(color))
        .frame(width: 24, height: 24)
        .overlay {
            if selected { Circle().strokeBorder(.primary, lineWidth: 2.5) }
        }
        .shadow(color: .black.opacity(0.12), radius: 1, y: 1)
        .onTapGesture { action() }
}

/// A swatch representing "no fill" (transparent): a white circle with a red
/// diagonal slash, always visible against any background.
private func noFillSwatch(selected: Bool, action: @escaping () -> Void) -> some View {
    ZStack {
        Circle()
            .fill(Color.white)
            .shadow(color: .black.opacity(0.12), radius: 1, y: 1)
        // Red diagonal slash
        Path { p in
            p.move(to:    CGPoint(x: 4, y: 20))
            p.addLine(to: CGPoint(x: 20, y: 4))
        }
        .stroke(Color.red, style: StrokeStyle(lineWidth: 2, lineCap: .round))
        // Selection ring
        if selected {
            Circle().strokeBorder(.primary, lineWidth: 2.5)
        } else {
            Circle().strokeBorder(Color.gray.opacity(0.3), lineWidth: 0.5)
        }
    }
    .frame(width: 24, height: 24)
    .contentShape(Circle())
    .onTapGesture { action() }
}

// MARK: - Stamp Controls

struct StampPaletteControls: View {

    var viewModel: AnnotationManagerViewModel

    var body: some View {
        HStack(spacing: 8) {
            Text("Stamps")
                .font(.caption)
                .foregroundStyle(.secondary)

            ForEach(viewModel.availableStamps) { stamp in
                Text(stamp.label)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color(stamp.color))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .overlay {
                        RoundedRectangle(cornerRadius: 4)
                            .strokeBorder(Color(stamp.color), lineWidth: 1.5)
                    }
            }
        }
    }
}

// MARK: - Text Box Controls

struct AddTextPaletteControls: View {
    @Bindable var viewModel: AnnotationManagerViewModel
    private let presetColors: [NSColor] = [.black, .systemRed, .systemBlue, .systemGreen, .white]
    private let fontSizes: [CGFloat] = [10, 12, 14, 16, 20, 24, 32]

    var body: some View {
        HStack(spacing: 12) {
            Label("Click to place a text box", systemImage: "textbox")
                .font(.caption)
                .foregroundStyle(.secondary)

            Divider().frame(height: 18)

            Text("Size")
                .font(.caption)
                .foregroundStyle(.secondary)

            Picker("", selection: Binding(
                get: { viewModel.textBoxFont.pointSize },
                set: { sz in
                    viewModel.textBoxFont = NSFont(name: viewModel.textBoxFont.fontName, size: sz)
                        ?? .systemFont(ofSize: sz)
                }
            )) {
                ForEach(fontSizes, id: \.self) { sz in
                    Text("\(Int(sz))").tag(sz)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 60)

            Divider().frame(height: 18)

            Text("Font")
                .font(.caption)
                .foregroundStyle(.secondary)

            Picker("", selection: Binding(
                get: { viewModel.textBoxFont.fontName },
                set: { name in
                    let sz = viewModel.textBoxFont.pointSize
                    viewModel.textBoxFont = NSFont(name: name, size: sz) ?? .systemFont(ofSize: sz)
                }
            )) {
                Text("System").tag(NSFont.systemFont(ofSize: 14).fontName)
                Text("Helvetica").tag("Helvetica")
                Text("Times").tag("Times-Roman")
                Text("Courier").tag("Courier")
                Text("Georgia").tag("Georgia")
                Text("Palatino").tag("Palatino-Roman")
            }
            .pickerStyle(.menu)
            .frame(width: 90)

            Divider().frame(height: 18)

            Text("Color")
                .font(.caption)
                .foregroundStyle(.secondary)

            ForEach(presetColors, id: \.self) { c in
                colorSwatch(c, selected: viewModel.textBoxColor == c) {
                    viewModel.textBoxColor = c
                }
            }
        }
    }
}

// MARK: - Shape Controls

struct ShapePaletteControls: View {
    @Bindable var viewModel: AnnotationManagerViewModel
    private let strokeColors: [NSColor] = [
        .systemRed, .systemBlue, .systemGreen, .systemOrange, .black, .systemPurple
    ]
    private let lineWidths: [CGFloat] = [1, 2, 3, 5, 8]

    var body: some View {
        HStack(spacing: 12) {
            // Shape type icon buttons
            HStack(spacing: 4) {
                ForEach(ShapeType.allCases) { type in
                    Button {
                        viewModel.shapeType = type
                    } label: {
                        Image(systemName: type.symbolName)
                            .font(.system(size: 15, weight: .medium))
                            .frame(width: 26, height: 26)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(viewModel.shapeType == type
                                ? Color.accentColor.opacity(0.18)
                                : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .help(type.rawValue)
                }
            }

            Divider().frame(height: 18)

            Text("Stroke")
                .font(.caption)
                .foregroundStyle(.secondary)

            ForEach(strokeColors, id: \.self) { c in
                colorSwatch(c, selected: viewModel.shapeStrokeColor == c) {
                    viewModel.shapeStrokeColor = c
                }
            }

            Divider().frame(height: 18)

            Text("Width")
                .font(.caption)
                .foregroundStyle(.secondary)

            Picker("", selection: $viewModel.shapeLineWidth) {
                ForEach(lineWidths, id: \.self) { w in
                    Text("\(Int(w))pt").tag(w)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 64)

            Divider().frame(height: 18)

            Text("Fill")
                .font(.caption)
                .foregroundStyle(.secondary)

            // "No fill" swatch — rendered as a strikethrough circle so it is
            // always visible and tappable regardless of the background colour.
            noFillSwatch(selected: viewModel.shapeFillColor == .clear) {
                viewModel.shapeFillColor = .clear
            }
            ForEach([NSColor.systemYellow, .systemBlue, .systemGreen, .white], id: \.self) { c in
                colorSwatch(c, selected: viewModel.shapeFillColor == c) {
                    viewModel.shapeFillColor = c
                }
            }
        }
    }
}
