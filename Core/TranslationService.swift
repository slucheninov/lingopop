import Foundation

final class TranslationService {

    let providers: [ProviderType: AIProvider] = [
        .claude: ClaudeProvider(),
        .openai: OpenAIProvider(),
        .gemini: GeminiProvider(),
        .googleFree: GoogleFreeProvider(),
        .googleCloud: GoogleCloudProvider(),
        .deepl: DeepLProvider(),
        .microsoftTranslator: MicrosoftTranslatorProvider()
    ]

    weak var usageStore: UsageStore?

    func provider(for type: ProviderType) throws -> AIProvider {
        guard let provider = providers[type] else {
            throw TranslationError.providerNotFound(type)
        }
        return provider
    }

    func execute(text: String, operation: AIOperation, config: ProviderConfig) async throws -> TranslationResult {
        let provider = try provider(for: config.providerType)
        let providerResult = try await provider.execute(
            text: text,
            operation: operation,
            config: config
        )
        recordUsage(providerResult.usage, provider: config.providerType, model: config.model, operation: operation)
        return TranslationResult(
            original: text,
            translated: providerResult.text,
            targetLanguage: config.targetLanguage,
            provider: config.providerType,
            operation: operation
        )
    }

    func recordUsage(_ usage: TokenUsage?, provider: ProviderType, model: String, operation: AIOperation) {
        guard let usage, let store = usageStore else { return }
        Task { @MainActor in
            store.append(UsageStore.Record(
                id: UUID(),
                timestamp: Date(),
                provider: provider,
                model: model,
                operation: operation,
                inputTokens: usage.inputTokens,
                outputTokens: usage.outputTokens
            ))
        }
    }
}
