// TipJarSettingsPane.swift
// Folio
//
// MIT License
// Copyright (c) 2026 Folio Contributors
//
// Settings pane that exposes the in-app Tip Jar so users can support
// development at any time after onboarding.

import SwiftUI

struct TipJarSettingsPane: View {

    @State private var tipJar = TipJarManager()

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Support Folio", systemImage: "heart.text.square.fill")
                        .font(.headline)
                        .symbolRenderingMode(.multicolor)
                    Text("Folio is free to use. Tips are completely optional and go directly towards new features and maintenance. Thank you for using Folio.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 4)
            }

            Section("Leave a Tip") {
                if tipJar.isWorking && tipJar.products.isEmpty {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Loading tip options…").foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                } else {
                    HStack(spacing: 12) {
                        ForEach(TipProduct.allCases) { tip in
                            TipPaneCard(tip: tip, tipJar: tipJar)
                        }
                    }
                    .padding(.vertical, 4)
                }

                if let purchased = tipJar.lastPurchasedID,
                   let _ = TipProduct(rawValue: purchased) {
                    Label("Thank you for your support!", systemImage: "sparkles")
                        .symbolRenderingMode(.multicolor)
                        .font(.callout.weight(.medium))
                        .foregroundStyle(Color.accentColor)
                }

                if let error = tipJar.lastError {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                        .font(.caption)
                }
            }

            Section("Other Ways to Support") {
                Link(destination: URL(string: "https://github.com/jonasgunklach/Folio")!) {
                    Label("Star the project on GitHub", systemImage: "star.fill")
                }
                Link(destination: URL(string: "https://github.com/jonasgunklach/Folio/issues")!) {
                    Label("Report an issue or suggest a feature", systemImage: "ladybug.fill")
                }
            }
        }
        .formStyle(.grouped)
        .padding(.vertical, 8)
        .task { await tipJar.loadProducts() }
    }
}

private struct TipPaneCard: View {

    let tip: TipProduct
    @Bindable var tipJar: TipJarManager

    var body: some View {
        Button {
            Task { await tipJar.purchase(tip) }
        } label: {
            VStack(spacing: 6) {
                Image(systemName: tip.symbolName)
                    .symbolRenderingMode(.multicolor)
                    .font(.system(size: 22))
                    .frame(height: 28)
                Text(tipJar.displayName(for: tip))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(tipJar.displayPrice(for: tip))
                    .font(.system(size: 13, weight: .semibold).monospacedDigit())
                    .foregroundStyle(Color.accentColor)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(NSColor.controlBackgroundColor))
                    .overlay {
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(Color.gray.opacity(0.25), lineWidth: 1)
                    }
            }
        }
        .buttonStyle(.plain)
        .disabled(tipJar.isWorking || tipJar.products[tip.rawValue] == nil)
        .opacity(tipJar.isWorking ? 0.55 : 1)
    }
}
