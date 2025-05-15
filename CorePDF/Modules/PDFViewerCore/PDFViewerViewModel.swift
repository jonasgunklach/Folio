// PDFViewerViewModel.swift
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
import PDFKit
import AVFoundation

/// Manages per-document viewer state: zoom level, display mode, TTS, and navigation.
/// Lives inside `PDFViewerView` as a `@State` object.
@MainActor
@Observable
final class PDFViewerViewModel {

    // MARK: - Display

    var displayMode: PDFDisplayMode = .singlePageContinuous
    var displayDirection: PDFDisplayDirection = .vertical

    // MARK: - Zoom

    private(set) var scaleFactor: CGFloat
    private static let minScale: CGFloat = 0.1
    private static let maxScale: CGFloat = 10.0

    init() {
        let zoom = CGFloat(SettingsStore.shared.defaultZoom)
        scaleFactor = zoom.clamped(to: Self.minScale...Self.maxScale)
    }

    func zoomIn() {
        scaleFactor = min(scaleFactor * 1.25, Self.maxScale)
    }

    func zoomOut() {
        scaleFactor = max(scaleFactor / 1.25, Self.minScale)
    }

    func zoomToFit() {
        scaleFactor = 1.0
    }

    func setScale(_ value: CGFloat) {
        scaleFactor = value.clamped(to: Self.minScale...Self.maxScale)
    }

    // MARK: - Text-to-Speech

    private let synthesizer = AVSpeechSynthesizer()
    var isTTSActive: Bool = false

    func toggleTTS(for page: PDFPage?) {
        guard let page else { return }
        if isTTSActive {
            synthesizer.stopSpeaking(at: .immediate)
            isTTSActive = false
        } else {
            let text = page.string ?? ""
            guard !text.isEmpty else { return }
            let utterance = AVSpeechUtterance(string: text)
            utterance.voice = AVSpeechSynthesisVoice(language: Locale.current.identifier)
            synthesizer.speak(utterance)
            isTTSActive = true
        }
    }

    func stopTTS() {
        synthesizer.stopSpeaking(at: .immediate)
        isTTSActive = false
    }

    // MARK: - Display Mode Helpers

    func toggleScrollDirection() {
        displayDirection = (displayDirection == .vertical) ? .horizontal : .vertical
    }

    func setTwoUpLayout(_ enabled: Bool) {
        displayMode = enabled ? .twoUpContinuous : .singlePageContinuous
    }
}

// MARK: - Comparable Clamp

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
