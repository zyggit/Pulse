import SwiftUI

// MARK: - Span picker

/// How far back the billing history shows.
enum SubscriptionBillingSpan: String, CaseIterable, Identifiable, Sendable {
    case threeMonths
    case sixMonths
    case twelveMonths
    case all

    var id: String { rawValue }

    var title: String {
        switch self {
        case .threeMonths: .localized("Last \("3") months")
        case .sixMonths: .localized("Last \("6") months")
        case .twelveMonths: .localized("Last \("12") months")
        case .all: .localized("All time")
        }
    }

    /// Nil means no cutoff.
    var monthCount: Int? {
        switch self {
        case .threeMonths: 3
        case .sixMonths: 6
        case .twelveMonths: 12
        case .all: nil
        }
    }
}

// MARK: - History section

/// Monthly billing history embedded in the subscription settings pane.
///
/// **All figures are what the reader recorded**, not derived from the current
/// standing price. A month with no record logged is omitted from the table, so
/// the rows that are there say something rather than echoing back the current
/// price for every month since the setting was created.
struct SubscriptionBillingHistoryView: View {
    let settings: AppSettings

    @State private var span: SubscriptionBillingSpan = .sixMonths
    /// The month being edited (format "YYYY-MM"), nil when nothing is open.
    @State private var editingMonth: String? = nil
    /// The account being edited within that month.
    @State private var editingAccount: String? = nil
    @State private var editingText: String = ""
    /// Whether the "log this month" sheet is open.
    @State private var isLogging = false
    /// Quick-log: pre-fill from current subscription prices for the current month.
    @State private var logMonth: String = ""

    // MARK: - Data

    /// Months within the chosen span, newest first.
    private var months: [String] {
        let all = settings.allBillingMonths()
        guard let cutoff = span.monthCount else { return all }
        let currentKey = AppSettings.billingMonthKey()
        let limit = monthsBefore(currentKey, count: cutoff)
        return all.filter { $0 >= limit }
    }

    /// All enabled subscription accounts (same as the main pane).
    private var accounts: [AccountKey] {
        settings.shownAccounts.filter { $0.provider.billing == .subscription }
    }

    /// How many distinct subscriptions have payments logged within the chosen span.
    private var recordedAccountsCount: Int {
        let allMonths = Set(months)
        return accounts.filter { account in
            guard let byMonth = settings.subscriptionBillingRecords[account.id] else { return false }
            return byMonth.keys.contains(where: { allMonths.contains($0) })
        }.count
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            spanAndLogGroup
            if months.isEmpty {
                emptyState
            } else {
                totalGroup
                chartGroup
                tableGroup
            }
        }
    }

    // MARK: - Span picker + Log button

    private var spanAndLogGroup: some View {
        SettingsGroup(String.localized("Billing history")) {
            SettingsRow(
                String.localized("Period"),
                subtitle: String.localized("Months with a recorded payment.")
            ) {
                HStack(spacing: 8) {
                    Picker("", selection: $span) {
                        ForEach(SubscriptionBillingSpan.allCases) { s in
                            Text(s.title).tag(s)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: SettingsLayout.controlWidth, alignment: .trailing)

                    Button(String.localized("Log payment")) {
                        logMonth = AppSettings.billingMonthKey()
                        isLogging = true
                    }
                    .sheet(isPresented: $isLogging) {
                        LogPaymentSheet(settings: settings, accounts: accounts,
                                        initialMonth: logMonth)
                    }
                }
            }
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        SettingsGroup(String.localized("Total")) {
            SettingsRow(
                String.localized("No payments recorded yet"),
                subtitle: String.localized("Record what was actually charged each month.")
            ) {
                EmptyView()
            }
        }
    }

    // MARK: - Period total

    private var totalGroup: some View {
        let totals = settings.billingTotals(months: months)
        return SettingsGroup(String.localized("Period total")) {
            VStack(alignment: .leading, spacing: 10) {
                // Main figure(s) — one per currency
                ForEach(totals.sorted(by: { $0.key < $1.key }), id: \.key) { pair in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(verbatim: SubscriptionSettingsView.format(pair.value, currency: pair.key))
                            .font(.system(size: 28, weight: .semibold))
                            .monospacedDigit()
                        Text(verbatim: pair.key)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                }

                // Summary captions
                HStack(spacing: 16) {
                    SpendCaption(
                        String.localized("Months recorded"),
                        "\(months.count)"
                    )
                    if accounts.count > 1 {
                        SpendCaption(
                            String.localized("Subscriptions"),
                            "\(recordedAccountsCount)"
                        )
                    }
                    // Average per month (single-currency only, to avoid apples-to-oranges)
                    if totals.count == 1, let total = totals.values.first, months.count > 1 {
                        let avg = total / Double(months.count)
                        let currency = totals.keys.first ?? "USD"
                        SpendCaption(
                            String.localized("Avg / month"),
                            SubscriptionSettingsView.format(avg, currency: currency)
                        )
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
    }

    // MARK: - Bar chart of monthly totals

    private var chartGroup: some View {
        // Build bars only for months that have at least one payment recorded.
        // Multi-currency: collapse to USD-equivalent is meaningless, so when
        // the reader uses more than one currency the chart shows the first one
        // only, with a note.
        let dominantCurrency = dominantCurrency()
        let bars: [BillingBar] = months.reversed().compactMap { month in
            let amount = monthTotal(month: month, currency: dominantCurrency)
            return BillingBar(monthKey: month, amount: amount)
        }

        return SettingsGroup(String.localized("By month")) {
            VStack(alignment: .leading, spacing: 4) {
                if bars.isEmpty {
                    SettingsRow(String.localized("No data in this period.")) { EmptyView() }
                } else {
                    BillingBarChart(bars: bars, currency: dominantCurrency)
                        .frame(height: 78)
                        .padding(.horizontal, 16)
                        .padding(.top, 14)
                        .padding(.bottom, 4)
                }
            }
        }
    }

    // MARK: - Month-by-month table

    private var tableGroup: some View {
        SettingsGroup(String.localized("Month by month")) {
            VStack(spacing: 0) {
                ForEach(Array(months.enumerated()), id: \.element) { index, month in
                    if index > 0 { SettingsRowDivider() }
                    monthRow(month)
                }
            }
        }
    }

    private func monthRow(_ month: String) -> some View {
        let totals = monthTotalsAllCurrencies(month: month)

        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(verbatim: displayMonth(month))
                    .font(.system(size: 13, weight: .medium))
                Spacer(minLength: 12)
                // Total for this month (all currencies)
                VStack(alignment: .trailing, spacing: 1) {
                    ForEach(totals.sorted(by: { $0.key < $1.key }), id: \.key) { pair in
                        Text(verbatim: SubscriptionSettingsView.format(pair.value, currency: pair.key))
                            .font(.system(size: 13, weight: .medium).monospacedDigit())
                    }
                    if totals.isEmpty {
                        Text(verbatim: "—")
                            .font(.system(size: 13).monospacedDigit())
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            // Per-account rows for this month
            ForEach(accounts, id: \.id) { account in
                accountBillingRow(account: account, month: month)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func accountBillingRow(account: AccountKey, month: String) -> some View {
        let recorded = settings.billingRecord(for: account, month: month)
        let currency = settings.subscriptionCurrency(for: account)
        let isEditingThis = editingMonth == month && editingAccount == account.id

        return HStack(spacing: 6) {
            LobeIconView(resource: account.provider.iconResource, size: 12)
                .foregroundStyle(.secondary)
            Text(verbatim: settings.label(for: account))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 8)

            if isEditingThis {
                TextField("0.00", text: $editingText)
                    .font(.system(size: 11).monospacedDigit())
                    .multilineTextAlignment(.trailing)
                    .frame(width: 72)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { commitEdit(account: account, month: month) }

                Button(String.localized("Save")) { commitEdit(account: account, month: month) }
                    .font(.system(size: 10))
                    .buttonStyle(.borderedProminent)
                    .controlSize(.mini)

                if recorded != nil {
                    Button(String.localized("Clear")) {
                        settings.setBillingRecord(nil, for: account, month: month)
                        editingMonth = nil
                        editingAccount = nil
                    }
                    .font(.system(size: 10))
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                }
            } else {
                Button {
                    editingText = recorded.map { String(format: "%.2f", $0) } ?? ""
                    editingMonth = month
                    editingAccount = account.id
                } label: {
                    if let recorded {
                        Text(verbatim: SubscriptionSettingsView.format(recorded, currency: currency))
                            .font(.system(size: 11).monospacedDigit())
                    } else {
                        Text(localized: "Add")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.accentColor)
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(recorded == nil ? Color.accentColor : Color.secondary)
            }
        }
    }

    // MARK: - Helpers

    private func commitEdit(account: AccountKey, month: String) {
        let value = Double(editingText.trimmingCharacters(in: .whitespacesAndNewlines))
        settings.setBillingRecord(value, for: account, month: month)
        editingMonth = nil
        editingAccount = nil
    }

    /// The most-used currency across all shown accounts (for the chart).
    private func dominantCurrency() -> String {
        var counts: [String: Int] = [:]
        for account in accounts {
            counts[settings.subscriptionCurrency(for: account), default: 0] += 1
        }
        return counts.max(by: { $0.value < $1.value })?.key ?? "USD"
    }

    /// Total amount for a single month and currency code.
    private func monthTotal(month: String, currency: String) -> Double {
        accounts
            .filter { settings.subscriptionCurrency(for: $0) == currency }
            .compactMap { settings.billingRecord(for: $0, month: month) }
            .reduce(0, +)
    }

    /// Per-currency totals for a single month.
    private func monthTotalsAllCurrencies(month: String) -> [String: Double] {
        var totals: [String: Double] = [:]
        for account in accounts {
            guard let amount = settings.billingRecord(for: account, month: month) else { continue }
            let currency = settings.subscriptionCurrency(for: account)
            totals[currency, default: 0] += amount
        }
        return totals
    }

    /// A `"YYYY-MM"` key N months before `ref`.
    private func monthsBefore(_ ref: String, count: Int) -> String {
        // Parse the key, subtract `count` months, re-format.
        let parts = ref.split(separator: "-")
        guard parts.count == 2,
              let year = Int(parts[0]),
              let month = Int(parts[1]) else { return ref }
        let totalMonths = year * 12 + month - count
        let y = totalMonths / 12
        let m = totalMonths % 12 == 0 ? 12 : totalMonths % 12
        let adjustedY = totalMonths % 12 == 0 ? y - 1 : y
        return String(format: "%04d-%02d", adjustedY, m)
    }

    /// Long month name for display — "October 2026" style.
    private func displayMonth(_ key: String) -> String {
        let parts = key.split(separator: "-")
        guard parts.count == 2,
              let year = Int(parts[0]),
              let month = Int(parts[1]) else { return key }
        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = 1
        guard let date = Calendar.current.date(from: comps) else { return key }
        return date.formatted(.dateTime.year().month(.wide).locale(LocalizationSource.locale))
    }
}

// MARK: - Bar chart for billing amounts

/// Monthly subscription spend as a bar chart, showing amounts rather than
/// token counts. Intentionally simple: no hover overlay, no emoji, just bars.
private struct BillingBar: Identifiable {
    let monthKey: String
    let amount: Double
    var id: String { monthKey }
}

private struct BillingBarChart: View {
    let bars: [BillingBar]
    let currency: String

    private static let maxBarWidth: CGFloat = 32

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            GeometryReader { proxy in
                let peak = max(bars.map(\.amount).max() ?? 1, 0.01)
                let slot = proxy.size.width / CGFloat(max(bars.count, 1))
                let width = max(min(slot * 0.72, Self.maxBarWidth), 1)

                HStack(alignment: .bottom, spacing: 0) {
                    ForEach(bars) { bar in
                        RoundedRectangle(cornerRadius: min(width, 6) / 2, style: .continuous)
                            .fill(bar.amount > 0 ? AnyShapeStyle(.tint) : AnyShapeStyle(.quaternary))
                            .frame(
                                width: width,
                                height: bar.amount > 0
                                    ? max((proxy.size.height - 1) * CGFloat(bar.amount) / CGFloat(peak), 3)
                                    : 2
                            )
                            .frame(width: slot, alignment: .center)
                            .help(SubscriptionSettingsView.format(bar.amount, currency: currency))
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(bar.monthKey)
                            .accessibilityValue(SubscriptionSettingsView.format(bar.amount, currency: currency))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(.quaternary)
                        .frame(height: 1)
                }
            }

            // End labels only
            if let first = bars.first, let last = bars.last, bars.count > 1 {
                HStack {
                    Text(verbatim: shortMonth(first.monthKey))
                    Spacer(minLength: 0)
                    Text(verbatim: shortMonth(last.monthKey))
                }
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(String.localized("Monthly billing"))
    }

    private func shortMonth(_ key: String) -> String {
        let parts = key.split(separator: "-")
        guard parts.count == 2,
              let year = Int(parts[0]),
              let month = Int(parts[1]) else { return key }
        var comps = DateComponents()
        comps.year = year; comps.month = month; comps.day = 1
        guard let date = Calendar.current.date(from: comps) else { return key }
        return date.formatted(.dateTime.month(.abbreviated).locale(LocalizationSource.locale))
    }
}

// MARK: - Log payment sheet

/// A sheet for quickly logging payments for the current month across all
/// subscriptions. Pre-fills each field from the standing price so the reader
/// only needs to correct exceptions.
private struct LogPaymentSheet: View {
    let settings: AppSettings
    let accounts: [AccountKey]
    let initialMonth: String

    @Environment(\.dismiss) private var dismiss

    @State private var selectedMonth: String = ""
    @State private var amounts: [String: String] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Title
            Text(localized: "Log payment")
                .font(.system(size: 17, weight: .semibold))

            // Month picker (current + last 11 months)
            HStack {
                Text(localized: "Month")
                    .font(.system(size: 13))
                Spacer()
                Picker("", selection: $selectedMonth) {
                    ForEach(recentMonths(), id: \.self) { key in
                        Text(verbatim: displayMonth(key)).tag(key)
                    }
                }
                .labelsHidden()
                .frame(width: 180)
            }

            Divider()

            // Per-account amount fields
            ForEach(Array(accounts.enumerated()), id: \.element.id) { index, account in
                if index > 0 { Divider() }
                accountRow(account)
            }

            Divider()

            HStack {
                Button(String.localized("Cancel")) { dismiss() }
                    .keyboardShortcut(.escape, modifiers: [])
                Spacer()
                Button(String.localized("Save")) { save() }
                    .keyboardShortcut(.return, modifiers: [])
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(minWidth: 360, idealWidth: 400)
        .onAppear {
            selectedMonth = initialMonth
            prefill()
        }
        .onChange(of: selectedMonth) { _, _ in prefill() }
    }

    private func accountRow(_ account: AccountKey) -> some View {
        let currency = settings.subscriptionCurrency(for: account)
        let binding = Binding(
            get: { amounts[account.id] ?? "" },
            set: { amounts[account.id] = $0 }
        )
        return HStack(spacing: 8) {
            LobeIconView(resource: account.provider.iconResource, size: 14)
                .foregroundStyle(.primary)
            Text(verbatim: settings.label(for: account))
                .font(.system(size: 13))
                .lineLimit(1)
            Spacer(minLength: 12)
            Text(verbatim: currency)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            TextField("0.00", text: binding)
                .font(.system(size: 12).monospacedDigit())
                .multilineTextAlignment(.trailing)
                .frame(width: 80)
                .textFieldStyle(.roundedBorder)
        }
    }

    private func prefill() {
        // Pre-fill from existing record if any, else from standing price.
        for account in accounts {
            let existing = settings.billingRecord(for: account, month: selectedMonth)
            if let existing {
                amounts[account.id] = String(format: "%.2f", existing)
            } else if let price = settings.subscriptionPrice(for: account) {
                amounts[account.id] = String(format: "%.2f", price)
            } else {
                amounts[account.id] = ""
            }
        }
    }

    private func save() {
        for account in accounts {
            let text = (amounts[account.id] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let value = Double(text)
            settings.setBillingRecord(value, for: account, month: selectedMonth)
        }
        dismiss()
    }

    private func recentMonths() -> [String] {
        let current = AppSettings.billingMonthKey()
        return (0..<12).map { offset in
            let parts = current.split(separator: "-")
            guard parts.count == 2,
                  let year = Int(parts[0]),
                  let month = Int(parts[1]) else { return current }
            let total = year * 12 + month - offset
            let y = total / 12
            let m = total % 12 == 0 ? 12 : total % 12
            let adjY = total % 12 == 0 ? y - 1 : y
            return String(format: "%04d-%02d", adjY, m)
        }
    }

    private func displayMonth(_ key: String) -> String {
        let parts = key.split(separator: "-")
        guard parts.count == 2,
              let year = Int(parts[0]),
              let month = Int(parts[1]) else { return key }
        var comps = DateComponents()
        comps.year = year; comps.month = month; comps.day = 1
        guard let date = Calendar.current.date(from: comps) else { return key }
        return date.formatted(.dateTime.year().month(.wide).locale(LocalizationSource.locale))
    }
}

#Preview("Billing history") {
    let settings = AppSettings()
    // Seed some demo data
    settings.subscriptionPrices["claudeCode"] = 20
    settings.subscriptionCurrencies["claudeCode"] = "USD"
    settings.subscriptionPrices["cursor"] = 20
    settings.subscriptionCurrencies["cursor"] = "USD"
    let months = ["2026-10", "2026-09", "2026-08", "2026-07"]
    for month in months {
        settings.setBillingRecord(20, for: AccountKey(.claudeCode), month: month)
        settings.setBillingRecord(20, for: AccountKey(.cursor), month: month)
    }
    return SubscriptionBillingHistoryView(settings: settings)
        .padding(24)
        .frame(width: 600)
}
