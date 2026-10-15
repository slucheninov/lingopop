import SwiftUI
import AppKit

struct UsageSettingsTab: View {
    @ObservedObject var store: UsageStore
    @State private var period: UsageStore.Period = .days30
    @State private var showResetConfirm = false

    private let trackedProviders = UsageFormatting.trackedProviders

    var body: some View {
        let t = store.totals(in: period)
        let byProvider = store.totalsByProvider(in: period)
        let buckets = store.chartBuckets(in: period)

        ScrollView {
            VStack(alignment: .leading, spacing: 12) {

                // Period picker + Reset
                HStack(alignment: .center, spacing: 10) {
                    Text("Period")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: true, vertical: false)
                    Picker("", selection: $period) {
                        Text("1 day").tag(UsageStore.Period.day)
                        Text("7 days").tag(UsageStore.Period.days7)
                        Text("30 days").tag(UsageStore.Period.days30)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 240)
                    Spacer()
                    Button("Reset stats…") { showResetConfirm = true }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .font(.callout)
                }

                // Summary cards
                HStack(spacing: 10) {
                    SummaryCard(
                        label: "Est. Cost",
                        value: t.estimatedCost.map { UsageFormatting.formatCost($0) } ?? "~$?",
                        subtitle: period.displayLabel,
                        valueColor: .red
                    )
                    SummaryCard(
                        label: "Tokens",
                        value: UsageFormatting.formatTokens(t.inputTokens + t.outputTokens),
                        subtitle: "in \(UsageFormatting.formatTokens(t.inputTokens)) · out \(UsageFormatting.formatTokens(t.outputTokens))"
                    )
                    SummaryCard(
                        label: "Calls",
                        value: "\(t.calls)",
                        subtitle: t.calls > 0
                            ? "avg \(UsageFormatting.formatTokens((t.inputTokens + t.outputTokens) / t.calls))/call"
                            : "no activity"
                    )
                }

                // Chart
                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(period.chartTitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)
                        TokenBarChartView(buckets: buckets, period: period)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                // Provider breakdown
                GroupBox {
                    VStack(spacing: 0) {
                        HStack(spacing: 0) {
                            Text("Provider").frame(width: 120, alignment: .leading)
                            Text("Input").frame(maxWidth: .infinity, alignment: .leading)
                            Text("Output").frame(maxWidth: .infinity, alignment: .leading)
                            Text("Calls").frame(width: 52, alignment: .leading)
                            Text("Est. Cost").frame(width: 80, alignment: .trailing)
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.bottom, 6)
                        Divider()
                        ForEach(Array(trackedProviders.enumerated()), id: \.element) { idx, provider in
                            ProviderBreakdownRow(provider: provider, totals: byProvider[provider])
                            if idx < trackedProviders.count - 1 {
                                Divider().padding(.leading, 120)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .padding(16)
        }
        .confirmationDialog(
            "Delete all usage history?",
            isPresented: $showResetConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) { store.reset() }
            Button("Cancel", role: .cancel) {}
        }
    }
}

// MARK: - Summary Card

private struct SummaryCard: View {
    let label: String
    let value: String
    let subtitle: String
    var valueColor: Color = .primary

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            Text(value)
                .font(.title2.monospacedDigit().weight(.semibold))
                .foregroundStyle(valueColor)
            Text(subtitle)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background)
        .cornerRadius(8)
    }
}

// MARK: - Provider Row

private struct ProviderBreakdownRow: View {
    let provider: ProviderType
    let totals: UsageStore.ProviderTotals?

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 6) {
                Circle()
                    .fill(provider.usageColor)
                    .frame(width: 8, height: 8)
                Text(provider.usageDisplayName)
                    .font(.callout)
            }
            .frame(width: 120, alignment: .leading)

            if let t = totals {
                Text(UsageFormatting.formatTokens(t.inputTokens))
                    .font(.callout.monospacedDigit())
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(UsageFormatting.formatTokens(t.outputTokens))
                    .font(.callout.monospacedDigit())
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("\(t.calls)")
                    .font(.callout)
                    .frame(width: 52, alignment: .leading)
                Text(t.estimatedCost.map { UsageFormatting.formatCost($0) } ?? "~$?")
                    .font(.callout.monospacedDigit().weight(.medium))
                    .foregroundStyle(provider.usageColor)
                    .frame(width: 80, alignment: .trailing)
            } else {
                Text("—").foregroundStyle(.tertiary).frame(maxWidth: .infinity, alignment: .leading)
                Text("—").foregroundStyle(.tertiary).frame(maxWidth: .infinity, alignment: .leading)
                Text("0").foregroundStyle(.tertiary).frame(width: 52, alignment: .leading)
                Text("—").foregroundStyle(.tertiary).frame(width: 80, alignment: .trailing)
            }
        }
        .padding(.vertical, 8)
    }
}

private extension UsageStore.Period {
    var displayLabel: String {
        switch self {
        case .day: return "today"
        case .days7: return "last 7 days"
        case .days30: return "last 30 days"
        }
    }

    var chartTitle: String {
        switch self {
        case .day: return "Hourly tokens · today"
        case .days7: return "Daily tokens · 7 days"
        case .days30: return "Daily tokens · 30 days"
        }
    }
}
