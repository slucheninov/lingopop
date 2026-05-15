import Foundation

protocol AIProvider {
    var type: ProviderType { get }
    var defaultBaseURL: String { get }
    var availableModels: [String] { get }
    var requiresApiKey: Bool { get }
    var supportedOperations: Set<AIOperation> { get }
    func execute(text: String, operation: AIOperation, config: ProviderConfig) async throws -> String
}

extension AIProvider {
    var requiresApiKey: Bool { true }
    var supportedOperations: Set<AIOperation> { Set(AIOperation.allCases) }
}
