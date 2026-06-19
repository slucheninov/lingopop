import Foundation

enum ProviderType: String, Codable, CaseIterable {
    case claude = "Claude"
    case openai = "OpenAI"
    case gemini = "Gemini"
    case googleFree = "Google (Free)"
    case googleCloud = "Google Translate"
    case deepl = "DeepL"
    case microsoftTranslator = "Microsoft Translator"
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

    static let `default` = ProviderConfig(
        providerType: .claude,
        apiKey: "",
        baseURL: "https://api.anthropic.com",
        model: "claude-haiku-4-5",
        targetLanguage: "Ukrainian",
        referer: nil,
        region: nil
    )
}
