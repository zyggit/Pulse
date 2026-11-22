// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import Foundation

extension AppSettings.Key {
    static let subscriptionPrices = "settings.subscriptionPrices"
    static let subscriptionCurrencies = "settings.subscriptionCurrencies"
    static let subscriptionInvoiceURLs = "settings.subscriptionInvoiceURLs"
    static let subscriptionBillingRecords = "settings.subscriptionBillingRecords"
}

extension AppSettings {
    func subscriptionPricesChanged(from old: [String: Double]) {
        guard subscriptionPrices != old else { return }
        defaults.set(subscriptionPrices, forKey: Key.subscriptionPrices)
    }

    func subscriptionCurrenciesChanged(from old: [String: String]) {
        guard subscriptionCurrencies != old else { return }
        defaults.set(subscriptionCurrencies, forKey: Key.subscriptionCurrencies)
    }

    func subscriptionInvoiceURLsChanged(from old: [String: String]) {
        guard subscriptionInvoiceURLs != old else { return }
        defaults.set(subscriptionInvoiceURLs, forKey: Key.subscriptionInvoiceURLs)
    }

    func subscriptionBillingRecordsChanged(from old: [String: [String: Double]]) {
        guard subscriptionBillingRecords != old else { return }
        defaults.set(subscriptionBillingRecords, forKey: Key.subscriptionBillingRecords)
    }

    func subscriptionPrice(for account: AccountKey) -> Double? {
        subscriptionPrices[account.id]
    }

    func setSubscriptionPrice(_ price: Double?, for account: AccountKey) {
        var updated = subscriptionPrices
        updated[account.id] = price
        subscriptionPrices = updated
    }

    func subscriptionCurrency(for account: AccountKey) -> String {
        subscriptionCurrencies[account.id] ?? "USD"
    }

    func setSubscriptionCurrency(_ currency: String, for account: AccountKey) {
        var updated = subscriptionCurrencies
        updated[account.id] = currency.isEmpty ? nil : currency
        subscriptionCurrencies = updated
    }

    func subscriptionInvoiceURL(for account: AccountKey) -> String {
        subscriptionInvoiceURLs[account.id] ?? ""
    }

    func setSubscriptionInvoiceURL(_ url: String, for account: AccountKey) {
        var updated = subscriptionInvoiceURLs
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        updated[account.id] = trimmed.isEmpty ? nil : trimmed
        subscriptionInvoiceURLs = updated
    }

    /// Total monthly subscription cost across all enabled subscription accounts,
    /// grouped by currency code. Accounts with no price entered are skipped.
    func monthlySubscriptionTotals() -> [String: Double] {
        var totals: [String: Double] = [:]
        for account in shownAccounts where account.provider.billing == .subscription {
            guard let price = subscriptionPrice(for: account) else { continue }
            let currency = subscriptionCurrency(for: account)
            totals[currency, default: 0] += price
        }
        return totals
    }

    /// The amount recorded for a specific account and calendar month.
    func billingRecord(for account: AccountKey, month: String) -> Double? {
        subscriptionBillingRecords[account.id]?[month]
    }

    /// Records (or clears) the amount paid for a specific month.
    ///
    /// `amount` of nil removes the entry. A zero is a valid record — a free
    /// month, or a waived charge — and is kept rather than treated as absent.
    func setBillingRecord(_ amount: Double?, for account: AccountKey, month: String) {
        var byAccount = subscriptionBillingRecords
        var byMonth = byAccount[account.id] ?? [:]
        byMonth[month] = amount
        byAccount[account.id] = byMonth.isEmpty ? nil : byMonth
        subscriptionBillingRecords = byAccount
    }

    /// All months that appear in any account's billing records, sorted newest
    /// first. Each entry is a `"YYYY-MM"` key.
    func allBillingMonths() -> [String] {
        var seen = Set<String>()
        for records in subscriptionBillingRecords.values {
            seen.formUnion(records.keys)
        }
        return seen.sorted().reversed()
    }

    /// Month key for a `Date` — `"YYYY-MM"` in the reader's calendar.
    static func billingMonthKey(for date: Date = Date(), calendar: Calendar = .current) -> String {
        let comps = calendar.dateComponents([.year, .month], from: date)
        return String(format: "%04d-%02d", comps.year ?? 0, comps.month ?? 0)
    }

    /// Total paid per currency across all enabled accounts for the given
    /// month keys. Used by the history view to compute period totals.
    func billingTotals(months: [String]) -> [String: Double] {
        var totals: [String: Double] = [:]
        for account in shownAccounts where account.provider.billing == .subscription {
            let currency = subscriptionCurrency(for: account)
            guard let byMonth = subscriptionBillingRecords[account.id] else { continue }
            for month in months {
                guard let amount = byMonth[month] else { continue }
                totals[currency, default: 0] += amount
            }
        }
        return totals
    }

    func restoreSubscriptions(from defaults: UserDefaults) {
        subscriptionPrices = defaults.dictionary(forKey: Key.subscriptionPrices) as? [String: Double] ?? [:]
        subscriptionCurrencies = defaults.dictionary(forKey: Key.subscriptionCurrencies) as? [String: String] ?? [:]
        subscriptionInvoiceURLs = defaults.dictionary(forKey: Key.subscriptionInvoiceURLs) as? [String: String] ?? [:]
        subscriptionBillingRecords = defaults.dictionary(forKey: Key.subscriptionBillingRecords) as? [String: [String: Double]] ?? [:]
    }
}
