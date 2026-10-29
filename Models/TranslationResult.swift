import Foundation

struct TranslationResult {
    let original: String
    let translated: String
    let targetLanguage: String
    let provider: ProviderType
    let operation: AIOperation
    var viaFallback: Bool = false
    var fallbackInfo: FallbackInfo? = nil
    var truncated: Bool = false
}
