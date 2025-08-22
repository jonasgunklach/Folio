// AIChatSidebarView.swift
// CorePDF
//
// MIT License
// Copyright (c) 2026 CorePDF Contributors

import SwiftUI
import PDFKit

// MARK: - AI Chat Sidebar

struct AIChatSidebarView: View {

    let document: PDFDocument?

    @State private var service = AIService()
    @State private var inputText: String = ""
    @FocusState private var inputFocused: Bool

    @Environment(SettingsStore.self) private var settings

    private var hasAPIKey: Bool {
        APIKeyStore.hasKey(for: settings.aiProvider)
    }

    var body: some View {
        VStack(spacing: 0) {
            // ── Header ────────────────────────────────────────────────
            HStack {
                Label("AI Assistant", systemImage: "sparkles")
                    .font(.headline)
                Spacer()
                if !service.messages.isEmpty {
                    Button {
                        service.clearHistory()
                    } label: {
                        Image(systemName: "trash")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Clear conversation")
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            Divider()

            // ── Messages ──────────────────────────────────────────────
            if !hasAPIKey {
                noKeyView
            } else if service.messages.isEmpty {
                emptyStateView
            } else {
                messagesView
            }

            Divider()

            // ── Input ─────────────────────────────────────────────────
            inputBar
                .padding(10)
        }
        .background(Color(NSColor.windowBackgroundColor))
    }

    // MARK: - Subviews

    private var messagesView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(service.messages) { message in
                        AIChatBubble(message: message)
                            .id(message.id)
                    }
                    if service.isLoading {
                        AIChatTypingIndicator()
                            .id("typing")
                    }
                }
                .padding(10)
            }
            .onChange(of: service.messages.count) {
                withAnimation {
                    if service.isLoading {
                        proxy.scrollTo("typing", anchor: .bottom)
                    } else {
                        proxy.scrollTo(service.messages.last?.id, anchor: .bottom)
                    }
                }
            }
            .onChange(of: service.isLoading) {
                withAnimation {
                    if service.isLoading {
                        proxy.scrollTo("typing", anchor: .bottom)
                    } else {
                        proxy.scrollTo(service.messages.last?.id, anchor: .bottom)
                    }
                }
            }
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 8) {
            Image(systemName: "sparkles")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
            Text("Ask anything about this document")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private var noKeyView: some View {
        VStack(spacing: 10) {
            Image(systemName: "key.slash")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
            Text("No API key configured")
                .font(.callout.bold())
            Text("Add your OpenAI or Claude API key in **Settings → AI**.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private var inputBar: some View {
        HStack(spacing: 8) {
            TextField("Ask about this PDF…", text: $inputText, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...4)
                .focused($inputFocused)
                .onSubmit { sendMessage() }
                .disabled(!hasAPIKey || service.isLoading)

            Button {
                sendMessage()
            } label: {
                Image(systemName: service.isLoading ? "stop.circle.fill" : "arrow.up.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(canSend ? Color.accentColor : .secondary)
            }
            .buttonStyle(.plain)
            .disabled(!canSend && !service.isLoading)
            .help(service.isLoading ? "Waiting for response…" : "Send")
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(NSColor.controlBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5)
                )
        )
    }

    private var canSend: Bool {
        hasAPIKey && !inputText.trimmingCharacters(in: .whitespaces).isEmpty && !service.isLoading
    }

    private func sendMessage() {
        guard canSend else { return }
        let question = inputText
        inputText = ""
        Task {
            await service.send(question: question, document: document)
        }
    }
}

// MARK: - Chat Bubble

struct AIChatBubble: View {

    let message: AIChatMessage

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            switch message.role {
            case .user:
                Spacer(minLength: 32)
                Text(message.content)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(Color.accentColor.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .textSelection(.enabled)

            case .assistant:
                Text(message.content)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(Color(NSColor.controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .textSelection(.enabled)
                Spacer(minLength: 32)

            case .error:
                Label(message.content, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(Color.red.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                Spacer(minLength: 32)
            }
        }
        .font(.callout)
    }
}

// MARK: - Typing Indicator

struct AIChatTypingIndicator: View {

    @State private var dotOffset: [CGFloat] = [0, 0, 0]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(Color.secondary.opacity(0.6))
                    .frame(width: 6, height: 6)
                    .offset(y: dotOffset[i])
                    .animation(
                        .easeInOut(duration: 0.5)
                        .repeatForever()
                        .delay(Double(i) * 0.15),
                        value: dotOffset[i]
                    )
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .onAppear {
            for i in 0..<3 { dotOffset[i] = -4 }
        }
    }
}
