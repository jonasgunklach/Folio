// AISettingsPane.swift
// CorePDF
//
// MIT License
// Copyright (c) 2026 CorePDF Contributors

import SwiftUI

struct AISettingsPane: View {

    @Environment(SettingsStore.self) private var settings

    // Local state for the key fields — displayed masked; only written to Keychain on commit
    @State private var openAIKeyDraft:    String = ""
    @State private var anthropicKeyDraft: String = ""
    @State private var groqKeyDraft:      String = ""
    @State private var openAIKeySaved:    Bool   = false
    @State private var anthropicKeySaved: Bool   = false
    @State private var groqKeySaved:      Bool   = false

    var body: some View {
        Form {
            // MARK: Provider & Model
            Section("Provider") {
                @Bindable var s = settings

                Picker("Provider", selection: $s.aiProvider) {
                    ForEach(AIProvider.allCases) { provider in
                        Label(provider.rawValue, systemImage: provider.symbolName)
                            .tag(provider)
                    }
                }
                .onChange(of: settings.aiProvider) {
                    // Reset model to the new provider's default if the current model isn't available
                    if !settings.aiProvider.availableModels.contains(settings.aiModel) {
                        settings.aiModel = settings.aiProvider.defaultModel
                    }
                }

                Picker("Model", selection: $s.aiModel) {
                    ForEach(settings.aiProvider.availableModels, id: \.self) { model in
                        Text(model).tag(model)
                    }
                }
            }

            // MARK: API Keys
            Section {
                apiKeyRow(
                    label: "OpenAI API Key",
                    placeholder: "sk-…",
                    provider: .openAI,
                    draft: $openAIKeyDraft,
                    isSaved: openAIKeySaved
                )

                apiKeyRow(
                    label: "Claude API Key",
                    placeholder: "sk-ant-…",
                    provider: .anthropic,
                    draft: $anthropicKeyDraft,
                    isSaved: anthropicKeySaved
                )

                apiKeyRow(
                    label: "Groq API Key",
                    placeholder: "gsk_…",
                    provider: .groq,
                    draft: $groqKeyDraft,
                    isSaved: groqKeySaved
                )
            } header: {
                Text("API Keys")
            } footer: {
                Text("Keys are stored securely in the macOS Keychain and never sent anywhere other than the selected provider's API endpoint.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear { refreshSavedState() }
    }

    // MARK: - API Key Row

    @ViewBuilder
    private func apiKeyRow(
        label: String,
        placeholder: String,
        provider: AIProvider,
        draft: Binding<String>,
        isSaved: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label)
                Spacer()
                if isSaved {
                    Label("Saved", systemImage: "checkmark.seal.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }
            HStack {
                SecureField(placeholder, text: draft)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))

                Button("Save") {
                    APIKeyStore.save(draft.wrappedValue, for: provider)
                    draft.wrappedValue = ""
                    refreshSavedState()
                }
                .disabled(draft.wrappedValue.trimmingCharacters(in: .whitespaces).isEmpty)

                if isSaved {
                    Button("Delete", role: .destructive) {
                        APIKeyStore.delete(for: provider)
                        refreshSavedState()
                    }
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func refreshSavedState() {
        openAIKeySaved    = APIKeyStore.hasKey(for: .openAI)
        anthropicKeySaved = APIKeyStore.hasKey(for: .anthropic)
        groqKeySaved      = APIKeyStore.hasKey(for: .groq)
    }
}
