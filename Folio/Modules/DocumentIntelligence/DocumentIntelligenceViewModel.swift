// DocumentIntelligenceViewModel.swift
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
import Vision
import CoreImage

/// Provides AI-assisted and image-processing capabilities:
/// - OCR via Vision `VNRecognizeTextRequest`
/// - Scan enhancement via CoreImage filters
/// - Summarization hook (local or remote API)
@MainActor
@Observable
final class DocumentIntelligenceViewModel {

    // MARK: - State

    var isProcessing: Bool = false
    var ocrResult: String = ""
    var summaryResult: String = ""
    var lastError: IntelligenceError?

    // MARK: - OCR

    /// Performs full-page OCR on the given PDFPage using Vision.
    /// Returns recognised text joined by newlines.
    func performOCR(on page: PDFPage) async {
        isProcessing = true
        defer { isProcessing = false }

        guard let cgImage = pageAsCGImage(page) else {
            lastError = .imageConversionFailed
            return
        }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.automaticallyDetectsLanguage = true

        do {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
                do {
                    try handler.perform([request])
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }

            let text = request.results?
                .compactMap { $0.topCandidates(1).first?.string }
                .joined(separator: "\n") ?? ""

            ocrResult = text.isEmpty ? "(No text recognised)" : text

        } catch {
            lastError = .visionError(error)
        }
    }

    // MARK: - Scan Enhancement

    /// Applies contrast boost and sharpening to a page image.
    /// Returns a CoreImage output suitable for display or re-embedding.
    func enhanceScan(page: PDFPage) -> CIImage? {
        guard let cgImage = pageAsCGImage(page) else { return nil }
        var image = CIImage(cgImage: cgImage)

        // 1. Boost contrast
        if let filter = CIFilter(name: "CIColorControls") {
            filter.setValue(image, forKey: kCIInputImageKey)
            filter.setValue(1.3, forKey: kCIInputContrastKey)
            filter.setValue(0.05, forKey: kCIInputBrightnessKey)
            if let output = filter.outputImage { image = output }
        }

        // 2. Sharpen
        if let filter = CIFilter(name: "CISharpenLuminance") {
            filter.setValue(image, forKey: kCIInputImageKey)
            filter.setValue(0.6, forKey: kCIInputSharpnessKey)
            if let output = filter.outputImage { image = output }
        }

        // 3. Adjust exposure
        if let filter = CIFilter(name: "CIExposureAdjust") {
            filter.setValue(image, forKey: kCIInputImageKey)
            filter.setValue(0.2, forKey: kCIInputEVKey)
            if let output = filter.outputImage { image = output }
        }

        return image
    }

    // MARK: - Summarisation Hook

    /// Placeholder for local LLM or API-based summarisation.
    /// Replace the body with a URLSession call or on-device model inference.
    func summarise(document: PDFDocument) async {
        isProcessing = true
        defer { isProcessing = false }

        // Gather all page text
        let fullText = (0..<document.pageCount)
            .compactMap { document.page(at: $0)?.string }
            .joined(separator: "\n\n")

        guard !fullText.isEmpty else {
            summaryResult = "No extractable text found in document."
            return
        }

        // TODO: Replace with actual model call (e.g., Ollama, OpenAI, Apple Intelligence)
        summaryResult = "Summary hook ready — \(fullText.count) characters extracted from \(document.pageCount) pages."
    }

    // MARK: - Helpers

    private func pageAsCGImage(_ page: PDFPage) -> CGImage? {
        let thumbnail = page.thumbnail(of: CGSize(width: 1800, height: 2400), for: .mediaBox)
        return thumbnail.cgImage(forProposedRect: nil, context: nil, hints: nil)
    }
}

// MARK: - Errors

enum IntelligenceError: LocalizedError {
    case imageConversionFailed
    case visionError(Error)
    case networkError(Error)

    var errorDescription: String? {
        switch self {
        case .imageConversionFailed:    "Could not render the page as an image."
        case .visionError(let e):       "Vision error: \(e.localizedDescription)"
        case .networkError(let e):      "Network error: \(e.localizedDescription)"
        }
    }
}
