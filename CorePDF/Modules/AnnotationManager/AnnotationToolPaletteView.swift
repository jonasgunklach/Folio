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

    var viewModel: AnnotationManagerViewModel
    var activeTool: ActiveTool

    var body: some View {
        HStack(spacing: 12) {
            switch activeTool {
            case .highlight:
                HighlightPaletteControls(viewModel: viewModel)
            case .underline:
                UnderlinePaletteControls(viewModel: viewModel)
            case .strikethrough:
                StrikethroughPaletteControls(viewModel: viewModel)
            case .freehand:
                FreehandPaletteControls(viewModel: viewModel)
            case .stamp:
                StampPaletteControls(viewModel: viewModel)
            case .text:
                Label("Click on the page to add a comment", systemImage: "bubble.left.fill")
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

// MARK: - Highlight Controls

struct HighlightPaletteControls: View {

    var viewModel: AnnotationManagerViewModel
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

            Slider(value: Binding(
                get: { viewModel.highlightOpacity },
                set: { viewModel.highlightOpacity = $0 }
            ), in: 0.1...1.0)
            .frame(width: 80)
        }
    }
}

// MARK: - Underline Controls

struct UnderlinePaletteControls: View {

    var viewModel: AnnotationManagerViewModel
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

    var viewModel: AnnotationManagerViewModel
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

// MARK: - Shared swatch helper

private func colorSwatch(_ color: NSColor, selected: Bool, action: @escaping () -> Void) -> some View {
    Circle()
        .fill(Color(color))
        .frame(width: 20, height: 20)
        .overlay {
            if selected { Circle().strokeBorder(.primary, lineWidth: 2) }
        }
        .onTapGesture { action() }
}

// MARK: - Freehand Controls

struct FreehandPaletteControls: View {

    var viewModel: AnnotationManagerViewModel

    var body: some View {
        HStack(spacing: 10) {
            Text("Color")
                .font(.caption)
                .foregroundStyle(.secondary)

            ColorPicker("", selection: Binding(
                get: { Color(viewModel.freehandColor) },
                set: { viewModel.freehandColor = NSColor($0) }
            ))
            .labelsHidden()

            Divider().frame(height: 18)

            Text("Width")
                .font(.caption)
                .foregroundStyle(.secondary)

            Slider(value: Binding(
                get: { viewModel.freehandLineWidth },
                set: { viewModel.freehandLineWidth = $0 }
            ), in: 0.5...10.0)
            .frame(width: 80)

            Text(String(format: "%.1f pt", viewModel.freehandLineWidth))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 42)
        }
    }
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
