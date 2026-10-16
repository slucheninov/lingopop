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
        case .translate: return String(localized: "Translate")
        case .grammarFix: return String(localized: "Fix grammar")
        case .rewrite: return String(localized: "Rewrite")
        case .explain: return String(localized: "Explain")
        case .screenTranslate: return String(localized: "Screen Translate")
        case .magic: return String(localized: "Magic")
        }
    }

    var shortName: String {
        switch self {
        case .translate: return String(localized: "Translation")
        case .grammarFix: return String(localized: "Grammar fix")
        case .rewrite: return String(localized: "Rewrite")
        case .explain: return String(localized: "Explanation")
        case .screenTranslate: return String(localized: "Screen Translation")
        case .magic: return String(localized: "Magic")
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
