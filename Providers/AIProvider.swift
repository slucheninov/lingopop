import Foundation

protocol AIProvider {
    var type: ProviderType { get }
    var defaultBaseURL: String { get }
    var availableModels: [String] { get }
    var requiresApiKey: Bool { get }
    var supportedOperations: Set<AIOperation> { get }
    var supportsVision: Bool { get }
    func execute(text: String, operation: AIOperation, config: ProviderConfig) async throws -> String
    func executeVision(image: Data, targetLanguage: String, config: ProviderConfig) async throws -> String
}

extension AIProvider {
    var requiresApiKey: Bool { true }
    var supportedOperations: Set<AIOperation> { Set(AIOperation.allCases) }
    var supportsVision: Bool { false }
    func executeVision(image: Data, targetLanguage: String, config: ProviderConfig) async throws -> String {
        throw TranslationError.operationNotSupported(provider: type, operation: .screenTranslate)
    }
}
