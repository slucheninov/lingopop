import Foundation

/// Identifies an AI / translation provider.
///
/// The `String` raw values are **persisted identifiers**, not display text: they appear in
/// `settings.json` / UserDefaults (as values and, via `ProviderKeyedDictionary`, as object keys),
/// in history and usage records, in the `LingoPop.secretHas.*` flags and in the `apiKey.<rawValue>`
/// account names of `SecretStorage`. They must never be renamed or reformatted; doing so orphans
/// stored data and API keys. Show `displayName` in the UI and in user-facing messages instead.
/// (Renaming a case identifier in Swift is fine; only the raw string is frozen.)
enum ProviderType: String, Codable, CaseIterable {
    case claude = "Claude"
    case openai = "OpenAI"
    case gemini = "Gemini"
    case grok = "Grok"
    case googleFree = "Google (Free)"
    case googleCloud = "Google Translate"
    case deepl = "DeepL"
    case microsoftTranslator = "Microsoft Translator"

    /// Human-readable name for UI and user-facing messages. Independent of `rawValue`, so it
    /// may be reworded freely (and localized later) without touching persisted data.
    var displayName: String {
        switch self {
        case .claude: return "Claude"
        case .openai: return "OpenAI"
        case .gemini: return "Gemini"
        case .grok: return "Grok"
        case .googleFree: return "Google (Free)"
        case .googleCloud: return "Google Translate"
        case .deepl: return "DeepL"
        case .microsoftTranslator: return "Microsoft Translator"
        }
    }
}

struct ProviderConfig: Codable, Equatable {
    var providerType: ProviderType
    var apiKey: String
    var baseURL: String
    var model: String
    var targetLanguage: String
    var magicPrompt: String = ""
    var referer: String?
    var region: String?
}
