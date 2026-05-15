import Foundation

enum AIOperation: String, Codable, CaseIterable, Hashable {
    case translate
    case grammarFix
    case rewrite

    var displayName: String {
        switch self {
        case .translate: return "Translate"
        case .grammarFix: return "Fix grammar"
        case .rewrite: return "Rewrite"
        }
    }

    var shortName: String {
        switch self {
        case .translate: return "Translation"
        case .grammarFix: return "Grammar fix"
        case .rewrite: return "Rewrite"
        }
    }

    var systemImage: String {
        switch self {
        case .translate: return "globe"
        case .grammarFix: return "checkmark.seal"
        case .rewrite: return "wand.and.stars"
        }
    }
}

enum PromptBuilder {
    static func systemPrompt(for operation: AIOperation, targetLanguage: String) -> String {
        switch operation {
        case .translate:
            return """
            You are a professional translator. Translate the following text to \(targetLanguage).
            Return only the translated text, no explanations, no original text, no quotes.
            """
        case .grammarFix:
            return """
            You are a grammar and spelling proofreader. Fix only grammar, spelling, and punctuation in the following text.
            Preserve the original meaning, style, language, tone, and formatting.
            Do not paraphrase or rewrite. Return only the corrected text, no explanations, no quotes.
            """
        case .rewrite:
            return """
            You are an editor. Rewrite the following text in the same language to fix any errors and improve clarity, flow, and style while preserving the original meaning, tone, and intent.
            Keep it natural — do not add information not present in the original.
            Return only the rewritten text, no explanations, no quotes.
            """
        }
    }
}
