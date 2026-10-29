import SwiftUI

/// Shared formatting and styling helpers for the Usage tab and its chart.
enum UsageFormatting {

    /// Providers that report token usage (the vision/LLM-capable ones), in display order.
    static let trackedProviders: [ProviderType] = [.claude, .openai, .gemini, .grok]

    static func formatTokens(_ n: Int) -> String {
        n >= 1000 ? String(format: "%.1fK", Double(n) / 1000) : "\(n)"
    }

    static func formatCost(_ cost: Double) -> String {
        if cost >= 0.01 { return String(format: "$%.2f", cost) }
        if cost >= 0.0001 { return String(format: "$%.4f", cost) }
        if cost > 0 { return "<$0.0001" }
        return "$0.00"
    }
}

extension ProviderType {
    var usageDisplayName: String {
        switch self {
        case .claude: return "Claude"
        case .openai: return "OpenAI"
        case .gemini: return "Gemini"
        case .grok: return "Grok"
        case .googleFree: return "Google Free"
        case .googleCloud: return "Google Cloud"
        case .deepl: return "DeepL"
        case .microsoftTranslator: return "Microsoft"
        }
    }

    var usageColor: Color {
        switch self {
        case .claude: return Color(.systemRed)
        case .openai: return Color(.systemGreen)
        case .gemini: return Color(.systemBlue)
        case .grok: return Color(.systemPurple)
        default: return .secondary
        }
    }
}
