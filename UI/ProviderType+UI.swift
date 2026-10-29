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

    /// Public page (rendered by GitHub) explaining how to get an API key for each provider.
    static let keyGuideBaseURL = "https://github.com/slucheninov/lingopop/blob/main/docs/api-keys.md"

    /// Fixed section anchor in `docs/api-keys.md`; the headings there must keep these ids.
    var keyGuideAnchor: String {
        switch self {
        case .claude: return "claude"
        case .openai: return "openai"
        case .gemini: return "gemini"
        case .grok: return "grok"
        case .googleFree: return "google-free"
        case .googleCloud: return "google-translate"
        case .deepl: return "deepl"
        case .microsoftTranslator: return "microsoft-translator"
        }
    }

    /// Deep link to this provider's section of the key guide. Falls back to the page itself,
    /// then to the repository root, so a malformed string can never crash the settings UI.
    var keyGuideURL: URL {
        URL(string: "\(Self.keyGuideBaseURL)#\(keyGuideAnchor)")
            ?? URL(string: Self.keyGuideBaseURL)
            ?? URL(fileURLWithPath: "/")
    }
}
