// OnboardingView.swift
// Folio
//
// MIT License
// Copyright (c) 2026 Folio Contributors
//
// Three-step first-launch onboarding flow:
//   1. Welcome — what Folio is, in one sentence.
//   2. Quick Setup — pick tab style and which annotation tools are visible.
//   3. Open Source & Tip Jar — invite users to support development.

import SwiftUI
import StoreKit

struct OnboardingView: View {

    @Environment(SettingsStore.self) private var settings
    @Environment(\.dismiss) private var dismiss

    @State private var step: Int = 0
    @State private var tipJar = TipJarManager()

    private let totalSteps = 3

    var body: some View {
        VStack(spacing: 0) {
            // ── Page content ──────────────────────────────────────────
            Group {
                switch step {
                case 0: WelcomeStep()
                case 1: SetupStep()
                default: TipJarStep(tipJar: tipJar)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .transition(.asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal:   .move(edge: .leading).combined(with: .opacity)
            ))

            // ── Page indicator + navigation ───────────────────────────
            VStack(spacing: 14) {
                HStack(spacing: 8) {
                    ForEach(0..<totalSteps, id: \.self) { i in
                        Capsule()
                            .fill(i == step ? Color.accentColor : Color.secondary.opacity(0.3))
                            .frame(width: i == step ? 22 : 8, height: 8)
                            .animation(.spring(response: 0.32, dampingFraction: 0.8), value: step)
                    }
                }

                HStack {
                    if step > 0 {
                        Button("Back") {
                            withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
                                step -= 1
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                    } else {
                        Button("Skip") { finish() }
                            .buttonStyle(.borderless)
                            .controlSize(.large)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button(step == totalSteps - 1 ? "Get Started" : "Continue") {
                        if step == totalSteps - 1 {
                            finish()
                        } else {
                            withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
                                step += 1
                            }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(24)
        }
        .frame(width: 560, height: 540)
        .task { await tipJar.loadProducts() }
    }

    private func finish() {
        settings.hasCompletedOnboarding = true
        dismiss()
    }
}

// MARK: - Step 1: Welcome

private struct WelcomeStep: View {
    var body: some View {
        VStack(spacing: 22) {
            Spacer()
            Image(systemName: "doc.richtext")
                .symbolRenderingMode(.multicolor)
                .font(.system(size: 80))
                .foregroundStyle(Color.accentColor)
                .padding(.bottom, 8)

            Text("Welcome to Folio")
                .font(.system(size: 30, weight: .bold))

            Text("A native macOS PDF editor — read, annotate, edit, and chat with your documents.")
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)

            Spacer()
            Spacer()
        }
        .padding(.horizontal, 40)
    }
}

// MARK: - Step 2: Quick Setup

private struct SetupStep: View {

    @Environment(SettingsStore.self) private var settings

    private let configurableTools: [ActiveTool] = [
        .markup, .text, .addText, .editText, .shape, .signature
    ]

    var body: some View {
        @Bindable var settings = settings

        ScrollView {
            VStack(spacing: 28) {

                // ── Header — same rhythm as Welcome & Tip Jar steps ───
                VStack(spacing: 14) {
                    Image(systemName: "slider.horizontal.3")
                        .symbolRenderingMode(.multicolor)
                        .font(.system(size: 56))
                        .foregroundStyle(Color.accentColor)

                    Text("Quick Setup")
                        .font(.system(size: 26, weight: .bold))

                    Text("Personalise Folio in two taps. You can change everything later in Settings (⌘,).")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 420)
                }
                .padding(.top, 16)

                // ── Tab Style cards ───────────────────────────────────
                VStack(spacing: 10) {
                    Text("Tab Style")
                        .font(.headline)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    HStack(spacing: 14) {
                        ForEach(TabBarStyle.allCases) { style in
                            OnboardingTabStyleCard(style: style,
                                                  isSelected: settings.tabBarStyle == style)
                                .onTapGesture { settings.tabBarStyle = style }
                        }
                        Spacer()
                    }
                }

                Divider()

                // ── Visible Tools ─────────────────────────────────────
                VStack(alignment: .leading, spacing: 10) {
                    Text("Tools in Toolbar")
                        .font(.headline)

                    Text("Pick the annotation tools you'll use most often.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 8)],
                              alignment: .leading, spacing: 8) {
                        ForEach(configurableTools) { tool in
                            ToolToggleChip(tool: tool, settings: settings)
                        }
                    }
                }

                Spacer(minLength: 8)
            }
            .padding(.horizontal, 40)
            .padding(.bottom, 16)
        }
    }
}

// MARK: - Tab Style visual card (onboarding)

private struct OnboardingTabStyleCard: View {

    let style: TabBarStyle
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 8) {
            // Mini window preview
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(NSColor.windowBackgroundColor))
                    .frame(width: 110, height: 72)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(isSelected ? Color.accentColor : Color.gray.opacity(0.3),
                                          lineWidth: isSelected ? 2 : 1)
                    )
                    .shadow(color: .black.opacity(0.10), radius: 4, y: 2)

                VStack(spacing: 0) {
                    // Toolbar strip
                    ZStack {
                        Color(NSColor.controlBackgroundColor)
                        if style == .toolbar {
                            // Tabs sit inside the toolbar
                            HStack(spacing: 4) {
                                Capsule()
                                    .fill(Color.accentColor.opacity(0.75))
                                    .frame(width: 26, height: 6)
                                Capsule()
                                    .fill(Color.gray.opacity(0.3))
                                    .frame(width: 18, height: 6)
                                Capsule()
                                    .fill(Color.gray.opacity(0.3))
                                    .frame(width: 18, height: 6)
                            }
                        }
                    }
                    .frame(height: 18)

                    // Dedicated tab bar strip (only for .bar)
                    if style == .bar {
                        ZStack {
                            Color(NSColor.windowBackgroundColor).opacity(0.85)
                            HStack(spacing: 4) {
                                Capsule()
                                    .fill(Color.accentColor.opacity(0.7))
                                    .frame(width: 26, height: 5)
                                Capsule()
                                    .fill(Color.gray.opacity(0.3))
                                    .frame(width: 18, height: 5)
                                Capsule()
                                    .fill(Color.gray.opacity(0.3))
                                    .frame(width: 18, height: 5)
                            }
                        }
                        .frame(height: 12)
                    }

                    // Page content area
                    HStack(spacing: 6) {
                        // Thumbnail sidebar strip
                        Color(NSColor.controlBackgroundColor).opacity(0.5)
                            .frame(width: 16)
                        // Content lines
                        VStack(spacing: 4) {
                            ForEach(0..<3, id: \.self) { i in
                                Capsule()
                                    .fill(Color.secondary.opacity(0.2))
                                    .frame(height: 3)
                                    .frame(maxWidth: i == 1 ? .infinity : CGFloat.random(in: 0.6...0.9) * 55)
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .frame(maxHeight: .infinity)
                    .padding(6)
                }
                .frame(width: 110, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            HStack(spacing: 4) {
                Text(style.rawValue)
                    .font(.caption)
                    .foregroundStyle(isSelected ? .primary : .secondary)
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.accentColor)
                        .font(.caption)
                }
            }
        }
        .contentShape(Rectangle())
        .animation(.easeInOut(duration: 0.15), value: isSelected)
    }
}

private struct ToolToggleChip: View {

    let tool: ActiveTool
    @Bindable var settings: SettingsStore

    var body: some View {
        let isOn = settings.visibleTools.contains(tool)
        Button {
            if isOn {
                guard settings.visibleTools.count > 1 else { return }
                settings.visibleTools.remove(tool)
            } else {
                settings.visibleTools.insert(tool)
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: tool.symbolName)
                    .symbolRenderingMode(.multicolor)
                    .frame(width: 20)
                Text(tool.rawValue)
                    .font(.callout)
                Spacer()
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isOn ? Color.accentColor : Color.secondary.opacity(0.5))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background {
                RoundedRectangle(cornerRadius: 9)
                    .fill(isOn ? Color.accentColor.opacity(0.1) : Color(NSColor.controlBackgroundColor))
                    .overlay {
                        RoundedRectangle(cornerRadius: 9)
                            .strokeBorder(
                                isOn ? Color.accentColor.opacity(0.5) : Color.gray.opacity(0.25),
                                lineWidth: 1
                            )
                    }
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Step 3: Tip Jar

private struct TipJarStep: View {

    @Bindable var tipJar: TipJarManager

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                Image(systemName: "heart.text.square.fill")
                    .symbolRenderingMode(.multicolor)
                    .font(.system(size: 56))
                    .foregroundStyle(Color.pink)
                    .padding(.top, 16)

                Text("Support Folio")
                    .font(.system(size: 24, weight: .bold))

                Text("Folio is free to use. If it saves you time, consider leaving a tip — it helps fund new features and keeps the project going.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 440)
                    .fixedSize(horizontal: false, vertical: true)

                if let purchased = tipJar.lastPurchasedID,
                   let tip = TipProduct(rawValue: purchased) {
                    thankYouCard(for: tip)
                        .transition(.scale.combined(with: .opacity))
                } else {
                    HStack(spacing: 12) {
                        ForEach(TipProduct.allCases) { tip in
                            TipCard(tip: tip, tipJar: tipJar)
                        }
                    }
                    .padding(.top, 4)
                }

                if let error = tipJar.lastError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }

                Spacer(minLength: 8)
            }
            .padding(.horizontal, 40)
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: tipJar.lastPurchasedID)
        }
    }

    private func thankYouCard(for tip: TipProduct) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "sparkles")
                .symbolRenderingMode(.multicolor)
                .font(.system(size: 32))
            Text("Thank You!")
                .font(.title3.bold())
            Text("Your support means the world.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.accentColor.opacity(0.12))
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Color.accentColor.opacity(0.4), lineWidth: 1)
                }
        }
    }
}

private struct TipCard: View {

    let tip: TipProduct
    @Bindable var tipJar: TipJarManager

    var body: some View {
        Button {
            Task { await tipJar.purchase(tip) }
        } label: {
            VStack(spacing: 8) {
                Image(systemName: tip.symbolName)
                    .symbolRenderingMode(.multicolor)
                    .font(.system(size: 28))
                    .frame(height: 36)

                Text(tipJar.displayName(for: tip))
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(tipJar.displayPrice(for: tip))
                    .font(.system(size: 15, weight: .semibold).monospacedDigit())
                    .foregroundStyle(Color.accentColor)
            }
            .frame(width: 120, height: 120)
            .background {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(NSColor.controlBackgroundColor))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(Color.gray.opacity(0.25), lineWidth: 1)
                    }
            }
        }
        .buttonStyle(.plain)
        .disabled(tipJar.isWorking || tipJar.products[tip.rawValue] == nil)
        .opacity(tipJar.isWorking ? 0.55 : 1)
    }
}
