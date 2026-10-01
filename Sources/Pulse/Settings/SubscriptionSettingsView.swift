import SwiftUI
import AppKit

/// Per-account subscription cost tracker.
///
/// **Nothing here is fetched.** Plan prices are not reported by any provider;
/// the reader enters them once and Pulse totals them up. The invoice URL is a
/// plain string that opens in the default browser on demand — no parsing, no
/// validation beyond checking it starts with a scheme.
///
/// Layout mirrors `TokenSpendView`: a header group followed by per-account
/// rows, so the two panes read as the same family.
struct SubscriptionSettingsView: View {
    let settings: AppSettings

    /// The account whose price field is being edited, so only one text field
    /// is active at a time and the keyboard does not fight itself.
    @State private var editingPrice: String? = nil
    @State private var priceText: String = ""
    @State private var editingURL: String? = nil
    @State private var urlText: String = ""
    @State private var editingCurrency: String? = nil

    /// The subscription accounts that are on the rail — the same set the
    /// overview totals. API accounts have no subscription price to enter.
    private var subscriptionAccounts: [AccountKey] {
        settings.shownAccounts.filter { $0.provider.billing == .subscription }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            totalGroup
            accountsGroup
            SubscriptionBillingHistoryView(settings: settings)
        }
    }

    // MARK: - Total

    private var totalGroup: some View {
        let totals = settings.monthlySubscriptionTotals()
        return SettingsGroup(String.localized("Monthly total")) {
            if totals.isEmpty {
                SettingsRow(
                    String.localized("No prices entered yet"),
                    subtitle: String.localized("Add a monthly price to each subscription below.")
                ) {
                    EmptyView()
                }
            } else {
                ForEach(Array(totals.sorted(by: { $0.key < $1.key }).enumerated()), id: \.element.key) { index, pair in
                    if index > 0 { SettingsRowDivider() }
                    SettingsRow(pair.key) {
                        Text(verbatim: Self.format(pair.value, currency: pair.key))
                            .font(.system(size: 13, weight: .semibold).monospacedDigit())
                    }
                }
            }
        }
    }

    // MARK: - Per account

    private var accountsGroup: some View {
        SettingsGroup(String.localized("Subscriptions")) {
            if subscriptionAccounts.isEmpty {
                SettingsRow(String.localized("No subscriptions on the rail.")) {
                    EmptyView()
                }
            } else {
                ForEach(Array(subscriptionAccounts.enumerated()), id: \.element.id) { index, account in
                    if index > 0 { SettingsRowDivider() }
                    accountRow(account)
                }
            }
        }
    }

    private func accountRow(_ account: AccountKey) -> some View {
        let price = settings.subscriptionPrice(for: account)
        let currency = settings.subscriptionCurrency(for: account)
        let invoiceURL = settings.subscriptionInvoiceURL(for: account)
        let isEditingThisPrice = editingPrice == account.id
        let isEditingThisURL = editingURL == account.id

        return VStack(alignment: .leading, spacing: 10) {
            // Header: provider mark + name
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                LobeIconView(resource: account.provider.iconResource, size: 15)
                    .foregroundStyle(.primary)
                    .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 4 }
                Text(verbatim: settings.label(for: account))
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                Spacer(minLength: 8)
                if let price {
                    Text(verbatim: Self.format(price, currency: currency))
                        .font(.system(size: 12).monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            // Monthly price row
            HStack(spacing: 8) {
                Text(localized: "Monthly price")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)

                // Currency picker (compact 3-letter code)
                currencyPicker(for: account)

                // Amount field
                if isEditingThisPrice {
                    TextField("0.00", text: $priceText)
                        .font(.system(size: 12).monospacedDigit())
                        .multilineTextAlignment(.trailing)
                        .frame(width: 72)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { commitPrice(for: account) }
                } else {
                    Button {
                        priceText = price.map { String(format: "%.2f", $0) } ?? ""
                        editingPrice = account.id
                        editingURL = nil
                    } label: {
                        Text(verbatim: price.map { String(format: "%.2f", $0) } ?? String.localized("Add price"))
                            .font(.system(size: 12).monospacedDigit())
                            .foregroundStyle(price == nil ? Color.accentColor : Color.primary)
                    }
                    .buttonStyle(.plain)
                }

                if isEditingThisPrice {
                    Button(String.localized("Save")) { commitPrice(for: account) }
                        .font(.system(size: 11))
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    if price != nil {
                        Button(String.localized("Clear")) {
                            settings.setSubscriptionPrice(nil, for: account)
                            editingPrice = nil
                        }
                        .font(.system(size: 11))
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
            }

            // Invoice / order URL row
            HStack(spacing: 8) {
                Text(localized: "Invoice / order URL")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)

                if isEditingThisURL {
                    TextField("https://…", text: $urlText)
                        .font(.system(size: 11))
                        .multilineTextAlignment(.trailing)
                        .frame(minWidth: 120, maxWidth: 200)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { commitURL(for: account) }
                    Button(String.localized("Save")) { commitURL(for: account) }
                        .font(.system(size: 11))
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    if !invoiceURL.isEmpty {
                        Button(String.localized("Clear")) {
                            settings.setSubscriptionInvoiceURL("", for: account)
                            editingURL = nil
                        }
                        .font(.system(size: 11))
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                } else if invoiceURL.isEmpty {
                    Button(String.localized("Add link")) {
                        urlText = ""
                        editingURL = account.id
                        editingPrice = nil
                    }
                    .font(.system(size: 12))
                    .foregroundStyle(Color.accentColor)
                    .buttonStyle(.plain)
                } else {
                    // Open link + edit side by side
                    HStack(spacing: 6) {
                        Button {
                            if let url = URL(string: invoiceURL) {
                                NSWorkspace.shared.open(url)
                            }
                        } label: {
                            HStack(spacing: 3) {
                                Image(systemName: "arrow.up.right.square")
                                    .font(.system(size: 10))
                                Text(localized: "Open")
                                    .font(.system(size: 12))
                            }
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Color.accentColor)

                        Button {
                            urlText = invoiceURL
                            editingURL = account.id
                            editingPrice = nil
                        } label: {
                            Image(systemName: "pencil")
                                .font(.system(size: 10))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: - Currency picker

    /// A compact inline picker showing the ISO code. The most common
    /// currencies first; the rest in alphabetical order after a divider.
    @ViewBuilder
    private func currencyPicker(for account: AccountKey) -> some View {
        let currency = settings.subscriptionCurrency(for: account)
        let isEditing = editingCurrency == account.id

        if isEditing {
            Picker("", selection: Binding(
                get: { settings.subscriptionCurrency(for: account) },
                set: {
                    settings.setSubscriptionCurrency($0, for: account)
                    editingCurrency = nil
                }
            )) {
                ForEach(Self.commonCurrencies, id: \.self) { code in
                    Text(verbatim: code).tag(code)
                }
                Divider()
                ForEach(Self.otherCurrencies, id: \.self) { code in
                    Text(verbatim: code).tag(code)
                }
            }
            .labelsHidden()
            .frame(width: 64)
        } else {
            Button {
                editingCurrency = account.id
            } label: {
                Text(verbatim: currency)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Helpers

    private func commitPrice(for account: AccountKey) {
        let value = Double(priceText.trimmingCharacters(in: .whitespacesAndNewlines))
        settings.setSubscriptionPrice(value, for: account)
        editingPrice = nil
    }

    private func commitURL(for account: AccountKey) {
        settings.setSubscriptionInvoiceURL(urlText, for: account)
        editingURL = nil
    }

    /// Formats an amount in the given ISO currency code using the reader's
    /// locale so a ¥ and a $ are both readable regardless of the language
    /// setting. Falls back to "AMOUNT CURRENCY" when the formatter cannot
    /// handle the code — an unknown code is always this user's own input.
    static func format(_ amount: Double, currency: String) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency
        formatter.locale = LocalizationSource.locale
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 2
        return formatter.string(from: NSNumber(value: amount))
            ?? String(format: "%.2f %@", amount, currency)
    }

    /// The handful of currencies a reader is most likely to use, shown at
    /// the top of the picker without scrolling.
    static let commonCurrencies = ["USD", "CNY", "EUR", "GBP", "JPY", "KRW", "HKD", "TWD"]

    /// Everything else, alphabetically. Keeping it short: the ones not in
    /// `commonCurrencies` that any AI service has been known to bill in.
    static let otherCurrencies = ["AUD", "CAD", "CHF", "INR", "MXN", "RUB", "SGD", "SEK", "NOK", "DKK"]
}

#Preview("Subscriptions") {
    let settings = AppSettings()
    return SubscriptionSettingsView(settings: settings)
        .padding(24)
        .frame(width: 600)
}
