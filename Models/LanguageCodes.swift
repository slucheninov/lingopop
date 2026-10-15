import Foundation

enum LanguageCodes {

    static let nameToCode: [String: String] = [
        "Ukrainian": "uk",
        "Russian": "ru",
        "English": "en",
        "German": "de",
        "Spanish": "es",
        "French": "fr",
        "Italian": "it",
        "Polish": "pl",
        "Portuguese": "pt",
        "Chinese": "zh",
        "Japanese": "ja",
        "Korean": "ko",
        "Turkish": "tr",
        "Arabic": "ar",
        "Dutch": "nl",
        "Czech": "cs",
        "Danish": "da",
        "Finnish": "fi",
        "Greek": "el",
        "Hebrew": "he",
        "Hindi": "hi",
        "Hungarian": "hu",
        "Indonesian": "id",
        "Norwegian": "no",
        "Romanian": "ro",
        "Swedish": "sv",
        "Thai": "th",
        "Vietnamese": "vi"
    ]

    static func code(for name: String) -> String {
        nameToCode[name] ?? name.lowercased()
    }

    /// DeepL expects uppercase codes and `NB` for Norwegian.
    static func deepLCode(for name: String) -> String {
        if name == "Norwegian" { return "NB" }
        return code(for: name).uppercased()
    }

    /// Microsoft Translator expects `nb` for Norwegian and `zh-Hans` for (simplified) Chinese.
    static func microsoftCode(for name: String) -> String {
        switch name {
        case "Norwegian": return "nb"
        case "Chinese": return "zh-Hans"
        default: return code(for: name)
        }
    }
}
