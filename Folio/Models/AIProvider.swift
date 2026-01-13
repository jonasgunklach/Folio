// AIProvider.swift
// CorePDF
//
// MIT License
// Copyright (c) 2026 CorePDF Contributors

import Foundation

// MARK: - AI Provider

enum AIProvider: String, CaseIterable, Identifiable, Codable {
    case openAI    = "OpenAI"
    case anthropic = "Claude (Anthropic)"
    case groq      = "Groq"

    var id: String { rawValue }

    var symbolName: String {
        switch self {
        case .openAI:    "sparkle"
        case .anthropic: "wand.and.sparkles"
        case .groq:      "bolt.fill"
        }
    }

    var defaultModel: String {
        switch self {
        case .openAI:    "gpt-4o"
        case .anthropic: "claude-opus-4-5"
        case .groq:      "llama-3.3-70b-versatile"
        }
    }

    var availableModels: [String] {
        switch self {
        case .openAI:    ["gpt-4o", "gpt-4o-mini", "gpt-4-turbo"]
        case .anthropic: ["claude-opus-4-5", "claude-sonnet-4-5", "claude-haiku-3-5"]
        case .groq:      ["llama-3.3-70b-versatile", "llama-3.1-8b-instant", "gemma2-9b-it", "mixtral-8x7b-32768"]
        }
    }

    /// Keychain service name for this provider's API key.
    var keychainService: String { "com.folio.apikey.\(rawValue.lowercased().replacingOccurrences(of: " ", with: "."))" }
}

// MARK: - Keychain API Key Store

/// Secure storage for API keys using the system Keychain.
/// Keys are stored per-provider and never written to UserDefaults.
enum APIKeyStore {

    private static let account = "apikey"

    static func save(_ key: String, for provider: AIProvider) {
        let data = Data(key.utf8)
        let query: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrService: provider.keychainService,
            kSecAttrAccount: account
        ]
        // Delete any existing entry first
        SecItemDelete(query as CFDictionary)

        guard !key.isEmpty else { return }

        let attributes: [CFString: Any] = [
            kSecClass:           kSecClassGenericPassword,
            kSecAttrService:     provider.keychainService,
            kSecAttrAccount:     account,
            kSecValueData:       data,
            kSecAttrAccessible:  kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        SecItemAdd(attributes as CFDictionary, nil)
    }

    static func load(for provider: AIProvider) -> String? {
        let query: [CFString: Any] = [
            kSecClass:            kSecClassGenericPassword,
            kSecAttrService:      provider.keychainService,
            kSecAttrAccount:      account,
            kSecReturnData:       true,
            kSecMatchLimit:       kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let key = String(data: data, encoding: .utf8)
        else { return nil }
        return key
    }

    static func delete(for provider: AIProvider) {
        let query: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrService: provider.keychainService,
            kSecAttrAccount: account
        ]
        SecItemDelete(query as CFDictionary)
    }

    static func hasKey(for provider: AIProvider) -> Bool {
        load(for: provider) != nil
    }
}
