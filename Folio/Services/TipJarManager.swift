// TipJarManager.swift
// Folio
//
// MIT License
// Copyright (c) 2026 Folio Contributors
//
// StoreKit 2 wrapper for the in-app "Tip Jar" — three consumable products
// users can purchase to support development. Configure the matching
// product IDs in App Store Connect (or in the included `Folio.storekit`
// configuration file for local testing).

import Foundation
import StoreKit

/// Identifiers for tip-jar products. Mirror these in App Store Connect.
enum TipProduct: String, CaseIterable, Identifiable, Sendable {
    case small  = "com.folio.tip.small"
    case medium = "com.folio.tip.medium"
    case large  = "com.folio.tip.large"

    var id: String { rawValue }

    /// Display label (used as a fallback if StoreKit hasn't loaded yet).
    var defaultTitle: String {
        switch self {
        case .small:  "Small Tip"
        case .medium: "Medium Tip"
        case .large:  "Generous Tip"
        }
    }

    /// SF Symbol used on the tip card.
    var symbolName: String {
        switch self {
        case .small:  "cup.and.saucer.fill"
        case .medium: "fork.knife"
        case .large:  "heart.fill"
        }
    }
}

@MainActor
@Observable
final class TipJarManager {

    // MARK: - State

    /// Loaded `Product` values keyed by product ID. Empty until `loadProducts()` succeeds.
    var products: [String: Product] = [:]

    /// `true` while StoreKit is fetching products or processing a purchase.
    var isWorking: Bool = false

    /// Last user-presentable error message, if any.
    var lastError: String?

    /// Set after a successful purchase so the UI can show a thank-you state.
    var lastPurchasedID: String?

    /// Excluded from `@Observable` synthesis so `nonisolated(unsafe)` applies
    /// to the plain stored var and deinit can cancel it without an isolation error.
    @ObservationIgnored
    private nonisolated(unsafe) var transactionListener: Task<Void, Never>?

    // MARK: - Init

    init() {
        // Listen for transactions that arrive outside the regular purchase flow
        // (e.g. interrupted purchases, Ask-to-Buy approvals, family sharing).
        transactionListener = Task { @MainActor [weak self] in
            for await update in Transaction.updates {
                if case .verified(let tx) = update {
                    await tx.finish()
                    self?.lastPurchasedID = tx.productID
                }
            }
        }
    }

    deinit {
        transactionListener?.cancel()
    }

    // MARK: - Loading

    /// Fetches localized product info from the App Store. Safe to call multiple times.
    func loadProducts() async {
        guard products.isEmpty else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            let fetched = try await Product.products(for: TipProduct.allCases.map(\.rawValue))
            for product in fetched {
                products[product.id] = product
            }
        } catch {
            lastError = "Could not load tip options: \(error.localizedDescription)"
        }
    }

    // MARK: - Purchasing

    /// Initiates a purchase for the given tip. Sets `lastPurchasedID` on success.
    func purchase(_ tip: TipProduct) async {
        guard let product = products[tip.rawValue] else {
            lastError = "Tip not available right now."
            return
        }
        isWorking = true
        defer { isWorking = false }
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                if case .verified(let tx) = verification {
                    await tx.finish()
                    lastPurchasedID = tx.productID
                    lastError = nil
                } else {
                    lastError = "Purchase could not be verified."
                }
            case .userCancelled:
                break
            case .pending:
                lastError = "Purchase is pending approval."
            @unknown default:
                break
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    // MARK: - Helpers

    /// Localized price string for the tip, or a placeholder if not yet loaded.
    func displayPrice(for tip: TipProduct) -> String {
        products[tip.rawValue]?.displayPrice ?? "—"
    }

    /// Localized name for the tip, or its default title if not yet loaded.
    func displayName(for tip: TipProduct) -> String {
        products[tip.rawValue]?.displayName ?? tip.defaultTitle
    }
}
