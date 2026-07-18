import Foundation

enum AIOperation: String, Codable, CaseIterable, Hashable {
    case translate
    case grammarFix
    case rewrite
    case explain
    case screenTranslate
    case magic

    var displayName: String {
        switch self {
        case .translate: return "Translate"
        case .grammarFix: return "Fix grammar"
        case .rewrite: return "Rewrite"
        case .explain: return "Explain"
        case .screenTranslate: return "Screen Translate"
        case .magic: return "Magic"
        }
    }

    var shortName: String {
        switch self {
        case .translate: return "Translation"
        case .grammarFix: return "Grammar fix"
        case .rewrite: return "Rewrite"
        case .explain: return "Explanation"
        case .screenTranslate: return "Screen Translation"
        case .magic: return "Magic"
        }
    }

    var systemImage: String {
        switch self {
        case .translate: return "globe"
        case .grammarFix: return "checkmark.seal"
        case .rewrite: return "wand.and.stars"
        case .explain: return "text.magnifyingglass"
        case .screenTranslate: return "camera.viewfinder"
        case .magic: return "sparkles"
        }
    }
}
