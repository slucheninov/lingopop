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
        if let code = nameToCode[name] { return code }
        if name.count == 2 { return name.lowercased() }
        return name.lowercased()
    }
}
