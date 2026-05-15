import Foundation
import NaturalLanguage

enum LanguageDetector {

    private static let mapping: [NLLanguage: String] = [
        .russian: "Russian",
        .ukrainian: "Ukrainian",
        .english: "English",
        .german: "German",
        .spanish: "Spanish",
        .french: "French",
        .italian: "Italian",
        .polish: "Polish",
        .portuguese: "Portuguese",
        .simplifiedChinese: "Chinese",
        .traditionalChinese: "Chinese",
        .japanese: "Japanese",
        .korean: "Korean",
        .turkish: "Turkish",
        .arabic: "Arabic",
        .dutch: "Dutch",
        .czech: "Czech",
        .danish: "Danish",
        .finnish: "Finnish",
        .greek: "Greek",
        .hebrew: "Hebrew",
        .hindi: "Hindi",
        .hungarian: "Hungarian",
        .indonesian: "Indonesian",
        .norwegian: "Norwegian",
        .romanian: "Romanian",
        .swedish: "Swedish",
        .thai: "Thai",
        .vietnamese: "Vietnamese"
    ]

    static func detect(_ text: String) -> String? {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        guard let lang = recognizer.dominantLanguage else { return nil }
        return mapping[lang]
    }
}
