import Foundation

extension SettingsStore {
    /// Picks the target language for `detectedSource`: with auto-detect on, looks the
    /// source up in `languagePairs`; falls back to `targetLanguage` otherwise.
    func resolveTargetLanguage(detectedSource: String?) -> String {
        guard useAutoDetect, let source = detectedSource else {
            return targetLanguage
        }
        if let mapped = languagePairs[source] {
            return mapped
        }
        return targetLanguage
    }
}
