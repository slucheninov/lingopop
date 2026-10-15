import SwiftUI

extension ProviderType {
    var sfSymbol: String {
        switch self {
        case .claude: return "sparkles"
        case .openai: return "circle.hexagongrid.fill"
        case .gemini: return "diamond.fill"
        case .grok: return "bolt.fill"
        case .googleFree: return "globe"
        case .googleCloud: return "character.book.closed.fill"
        case .deepl: return "text.bubble.fill"
        case .microsoftTranslator: return "textformat.abc"
        }
    }

    var iconColor: Color {
        switch self {
        case .claude: return Color(red: 0.851, green: 0.467, blue: 0.341)
        case .openai: return Color.primary
        case .gemini: return Color(red: 0.259, green: 0.522, blue: 0.957)
        case .grok: return Color(red: 0.557, green: 0.267, blue: 0.678)
        case .googleFree: return Color(red: 0.204, green: 0.659, blue: 0.325)
        case .googleCloud: return Color(red: 0.259, green: 0.522, blue: 0.957)
        case .deepl: return Color(red: 0.176, green: 0.322, blue: 0.478)
        case .microsoftTranslator: return Color(red: 0.0, green: 0.643, blue: 0.937)
        }
    }
}
