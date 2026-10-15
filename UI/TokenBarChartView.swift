import SwiftUI
import AppKit

struct TokenBarChartView: View {
    let buckets: [UsageStore.Bucket]
    var period: UsageStore.Period = .days30

    private static let providerOrder: [ProviderType] = [.claude, .openai, .gemini, .grok]
    private static let providerColors: [ProviderType: Color] = [
        .claude: Color(.systemRed),
        .openai: Color(.systemGreen),
        .gemini: Color(.systemBlue),
        .grok: Color(.systemPurple)
    ]

    private var xAxisLabels: [String] {
        switch period {
        case .day:
            return (0..<buckets.count).map { i in i % 6 == 0 ? "\(i)" : "" }
        case .days7:
            let fmt = DateFormatter()
            fmt.dateFormat = "EEE"
            return buckets.map { fmt.string(from: $0.start) }
        case .days30:
            return buckets.enumerated().map { i, b in
                i % 5 == 0 ? "\(Calendar.current.component(.day, from: b.start))" : ""
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Canvas { ctx, size in
                guard !buckets.isEmpty else { return }
                let maxTokens = buckets.map { bucket in
                    bucket.byProvider.values.reduce(0) { $0 + $1.input + $1.output }
                }.max() ?? 1

                let gap: CGFloat = 3
                let barWidth = (size.width - gap * CGFloat(buckets.count - 1)) / CGFloat(buckets.count)

                for (i, bucket) in buckets.enumerated() {
                    let x = CGFloat(i) * (barWidth + gap)
                    var yOffset = size.height

                    for provider in Self.providerOrder {
                        guard let tokens = bucket.byProvider[provider] else { continue }
                        let total = tokens.input + tokens.output
                        guard total > 0 else { continue }
                        let barH = CGFloat(total) / CGFloat(maxTokens) * size.height
                        let color = Self.providerColors[provider] ?? .secondary
                        let rect = CGRect(x: x, y: yOffset - barH, width: max(barWidth, 1), height: barH)
                        ctx.fill(Path(roundedRect: rect, cornerRadius: 2), with: .color(color))
                        yOffset -= barH
                    }
                }
            }
            .frame(height: 60)

            HStack(spacing: 3) {
                ForEach(Array(xAxisLabels.enumerated()), id: \.offset) { _, label in
                    Text(label)
                        .font(.caption2)
                        .foregroundColor(Color.secondary.opacity(0.6))
                        .frame(maxWidth: .infinity)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
            .frame(height: 14)

            HStack(spacing: 12) {
                ForEach(Self.providerOrder, id: \.self) { provider in
                    HStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Self.providerColors[provider] ?? .secondary)
                            .frame(width: 10, height: 10)
                        Text(provider.chartLabel)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

private extension ProviderType {
    var chartLabel: String {
        switch self {
        case .claude: return "Claude"
        case .openai: return "OpenAI"
        case .gemini: return "Gemini"
        case .grok: return "Grok"
        default: return rawValue
        }
    }
}
