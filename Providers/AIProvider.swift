import Foundation

/// Editable per-provider settings fields shown in the Providers tab.
enum ProviderField: Hashable {
    case apiKey, baseURL, model, referer, region
}

protocol AIProvider {
    var type: ProviderType { get }
    var defaultBaseURL: String { get }
    var availableModels: [String] { get }
    var requiresApiKey: Bool { get }
    var supportedOperations: Set<AIOperation> { get }
    var supportsVision: Bool { get }
    /// True when an empty base URL means "auto-select the endpoint" (e.g. DeepL free vs pro by key).
    var autoBaseURL: Bool { get }
    /// Settings fields the Providers tab renders for this provider. The model field is
    /// still hidden when `availableModels` is empty.
    var settingsFields: [ProviderField] { get }
    func execute(text: String, operation: AIOperation, config: ProviderConfig) async throws -> ProviderResult
    func executeVision(image: Data, targetLanguage: String, config: ProviderConfig) async throws -> ProviderResult
}

extension AIProvider {
    var requiresApiKey: Bool { true }
    var supportedOperations: Set<AIOperation> { Set(AIOperation.allCases) }
    var supportsVision: Bool { false }
    var autoBaseURL: Bool { false }
    var settingsFields: [ProviderField] {
        requiresApiKey ? [.apiKey, .baseURL, .model] : [.baseURL, .model]
    }
    func executeVision(image: Data, targetLanguage: String, config: ProviderConfig) async throws -> ProviderResult {
        throw TranslationError.operationNotSupported(provider: type, operation: .screenTranslate)
    }

    func mimeType(for data: Data) -> String {
        guard data.count >= 4 else { return "image/png" }
        let header = data.prefix(4)
        // PNG signature: 89 50 4E 47
        if header.starts(with: [0x89, 0x50, 0x4E, 0x47]) { return "image/png" }
        // JPEG signature: FF D8 FF
        if header.starts(with: [0xFF, 0xD8, 0xFF]) { return "image/jpeg" }
        return "image/png"
    }
}
