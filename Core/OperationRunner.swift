import Foundation
import os

struct OperationRunOutcome {
    let result: TranslationResult
    let detectedSource: String?
    let viaFallback: Bool
}

@MainActor
final class OperationRunner {
    private let settingsStore: SettingsStore
    private let translationService: TranslationService
    private let log = Logger(subsystem: "com.lingopop.app", category: "OperationRunner")

    init(settingsStore: SettingsStore, translationService: TranslationService) {
        self.settingsStore = settingsStore
        self.translationService = translationService
    }

    func run(
        operation: AIOperation,
        text: String,
        detectedSource: String?,
        targetLanguage: String,
        primary: ProviderType,
        allowFallback: Bool
    ) async throws -> OperationRunOutcome {
        let primaryConfig = settingsStore.config(for: primary, overrideTargetLanguage: targetLanguage)
        try validateProvider(primary, config: primaryConfig, operation: operation)

        do {
            let result = try await translationService.execute(text: text, operation: operation, config: primaryConfig)
            return OperationRunOutcome(result: result, detectedSource: detectedSource, viaFallback: false)
        } catch let primaryError as TranslationError {
            if allowFallback,
               let fallback = settingsStore.fallback(for: primary),
               fallback != primary,
               shouldRetryWithFallback(primaryError) {
                let fallbackConfig = settingsStore.config(for: fallback, overrideTargetLanguage: targetLanguage)
                do {
                    try validateProvider(fallback, config: fallbackConfig, operation: operation)
                    var result = try await translationService.execute(text: text, operation: operation, config: fallbackConfig)
                    result.viaFallback = true
                    result.fallbackInfo = FallbackInfo(primaryProvider: primary, error: primaryError)
                    return OperationRunOutcome(result: result, detectedSource: detectedSource, viaFallback: true)
                } catch {
                    log.error("Fallback also failed: \(error.localizedDescription, privacy: .public)")
                }
            }
            throw primaryError
        }
    }

    private func validateProvider(_ provider: ProviderType, config: ProviderConfig, operation: AIOperation) throws {
        let impl = try translationService.provider(for: provider)
        guard impl.supportedOperations.contains(operation) else {
            throw TranslationError.operationNotSupported(provider: provider, operation: operation)
        }
        if impl.requiresApiKey, config.apiKey.isEmpty {
            throw TranslationError.missingApiKey
        }
    }

    private func shouldRetryWithFallback(_ error: TranslationError) -> Bool {
        switch error {
        case .http(let status, _, _):
            return status == 429 || (500...599).contains(status)
        case .network:
            return true
        case .invalidURL, .missingApiKey, .decoding, .emptyResponse, .operationNotSupported,
             .invalidConfiguration, .providerNotFound:
            return false
        }
    }
}
