import Foundation
import NaturalLanguage

enum LanguageDetector {

    /// Detects the dominant language of `text` and maps it to a name from the
    /// `Languages.all` table (nil if undetectable or unsupported).
    static func detect(_ text: String) -> String? {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        guard let lang = recognizer.dominantLanguage else { return nil }
        return Languages.name(for: lang)
    }
}
