import Foundation

final class TranslationService {

    let providers: [ProviderType: AIProvider] = [
        .claude: ClaudeProvider(),
        .openai: OpenAIProvider(),
        .gemini: GeminiProvider(),
        .googleFree: GoogleFreeProvider(),
        .googleCloud: GoogleCloudProvider()
    ]

    func provider(for type: ProviderType) -> AIProvider {
        providers[type]!
    }

    func execute(text: String, operation: AIOperation, config: ProviderConfig) async throws -> TranslationResult {
        let provider = provider(for: config.providerType)
        let result = try await provider.execute(
            text: text,
            operation: operation,
            config: config
        )
        return TranslationResult(
            original: text,
            translated: result,
            targetLanguage: config.targetLanguage,
            provider: config.providerType,
            operation: operation
        )
    }
}
