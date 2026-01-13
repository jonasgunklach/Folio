// AIService.swift
// CorePDF
//
// MIT License
// Copyright (c) 2026 CorePDF Contributors

import Foundation
import PDFKit

// MARK: - Chat Message

struct AIChatMessage: Identifiable, Equatable {
    enum Role { case user, assistant, error }
    let id   = UUID()
    let role:    Role
    let content: String
}

// MARK: - AI Service

/// Sends questions about a PDF to the configured AI provider.
/// API keys are read from the Keychain; never stored in memory longer than needed.
@MainActor
@Observable
final class AIService {

    var messages: [AIChatMessage] = []
    var isLoading: Bool = false

    private let settings = SettingsStore.shared

    // MARK: - Public

    func send(question: String, document: PDFDocument?) async {
        guard !question.trimmingCharacters(in: .whitespaces).isEmpty else { return }

        let apiKey = APIKeyStore.load(for: settings.aiProvider) ?? ""
        guard !apiKey.isEmpty else {
            messages.append(AIChatMessage(
                role: .error,
                content: "No API key configured. Add one in Settings → AI."
            ))
            return
        }

        messages.append(AIChatMessage(role: .user, content: question))
        isLoading = true
        defer { isLoading = false }

        let context = documentContext(from: document)

        do {
            let reply: String
            switch settings.aiProvider {
            case .openAI:
                reply = try await callOpenAI(question: question, context: context, apiKey: apiKey)
            case .anthropic:
                reply = try await callAnthropic(question: question, context: context, apiKey: apiKey)
            case .groq:
                reply = try await callGroq(question: question, context: context, apiKey: apiKey)
            }
            messages.append(AIChatMessage(role: .assistant, content: reply))
        } catch {
            messages.append(AIChatMessage(role: .error, content: "Error: \(error.localizedDescription)"))
        }
    }

    func clearHistory() {
        messages.removeAll()
    }

    // MARK: - Document Context

    private func documentContext(from document: PDFDocument?) -> String {
        guard let document else { return "" }
        // Use PDFKit text extraction; cap at ~12 000 chars to keep token usage reasonable
        let full = document.string ?? ""
        let cap  = 12_000
        if full.count > cap {
            return String(full.prefix(cap)) + "\n…[document truncated for length]"
        }
        return full
    }

    // MARK: - OpenAI

    private func callOpenAI(question: String, context: String, apiKey: String) async throws -> String {
        let url = URL(string: "https://api.openai.com/v1/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let systemPrompt = context.isEmpty
            ? "You are a helpful assistant for a PDF reader application."
            : "You are a helpful assistant. Answer questions about the following PDF document.\n\nDocument content:\n\(context)"

        let body: [String: Any] = [
            "model": settings.aiModel,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user",   "content": question]
            ],
            "max_tokens": 1024
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        try validateHTTPResponse(response, data: data, provider: .openAI)

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let choices = json?["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String
        else { throw AIError.unexpectedResponse }
        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Anthropic

    private func callAnthropic(question: String, context: String, apiKey: String) async throws -> String {
        let url = URL(string: "https://api.anthropic.com/v1/messages")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let systemPrompt = context.isEmpty
            ? "You are a helpful assistant for a PDF reader application."
            : "You are a helpful assistant. Answer questions about the following PDF document.\n\nDocument content:\n\(context)"

        let body: [String: Any] = [
            "model":      settings.aiModel,
            "max_tokens": 1024,
            "system":     systemPrompt,
            "messages":   [["role": "user", "content": question]]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        try validateHTTPResponse(response, data: data, provider: .anthropic)

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let content = (json?["content"] as? [[String: Any]])?.first,
              let text = content["text"] as? String
        else { throw AIError.unexpectedResponse }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Groq (OpenAI-compatible)

    private func callGroq(question: String, context: String, apiKey: String) async throws -> String {
        let url = URL(string: "https://api.groq.com/openai/v1/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let systemPrompt = context.isEmpty
            ? "You are a helpful assistant for a PDF reader application."
            : "You are a helpful assistant. Answer questions about the following PDF document.\n\nDocument content:\n\(context)"

        let body: [String: Any] = [
            "model": settings.aiModel,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user",   "content": question]
            ],
            "max_tokens": 1024
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        try validateHTTPResponse(response, data: data, provider: .groq)

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let choices = json?["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String
        else { throw AIError.unexpectedResponse }
        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Helpers

    private func validateHTTPResponse(_ response: URLResponse, data: Data, provider: AIProvider) throws {
        guard let http = response as? HTTPURLResponse else { throw AIError.unexpectedResponse }
        guard (200..<300).contains(http.statusCode) else {
            // Try to surface the provider's error message
            let errorMessage: String
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                switch provider {
                case .openAI, .groq:
                    errorMessage = (json["error"] as? [String: Any])?["message"] as? String
                        ?? "HTTP \(http.statusCode)"
                case .anthropic:
                    errorMessage = json["error"] as? String
                        ?? (json["error"] as? [String: Any])?["message"] as? String
                        ?? "HTTP \(http.statusCode)"
                }
            } else {
                errorMessage = "HTTP \(http.statusCode)"
            }
            throw AIError.apiError(errorMessage)
        }
    }
}

// MARK: - Errors

enum AIError: LocalizedError {
    case unexpectedResponse
    case apiError(String)

    var errorDescription: String? {
        switch self {
        case .unexpectedResponse:   return "Unexpected response format from AI provider."
        case .apiError(let msg):    return msg
        }
    }
}
