import AppKit

/// Presents operation outcomes (result / failure) in the popup and status icon,
/// records history, and answers "which providers can Retry / Translate use".
@MainActor
final class OperationPresenter {
    private let popup: PopupWindow
    private let statusController: StatusItemController
    private let settingsStore: SettingsStore
    private let historyStore: TranslationHistoryStore
    private let translationService: TranslationService

    init(
        popup: PopupWindow,
        statusController: StatusItemController,
        settingsStore: SettingsStore,
        historyStore: TranslationHistoryStore,
        translationService: TranslationService
    ) {
        self.popup = popup
        self.statusController = statusController
        self.settingsStore = settingsStore
        self.historyStore = historyStore
        self.translationService = translationService
    }

    /// Shows `failure` in the popup (error status icon, optional Retry providers and,
    /// when `anchor` is given, the popup itself). The single error-presentation path.
    func presentFailure(_ failure: PopupError, retryProviders: [ProviderType] = [], near anchor: NSPoint? = nil) {
        statusController.apply(.error)
        popup.state.setError(failure)
        popup.state.availableRetryProviders = retryProviders
        if let anchor { popup.show(near: anchor) }
    }

    /// Maps any error through `PopupError.from`. `CancellationError` is never presented.
    func presentFailure(_ error: Error, retryProviders: [ProviderType] = [], near anchor: NSPoint? = nil) {
        guard !(error is CancellationError) else { return }
        presentFailure(PopupError.from(error), retryProviders: retryProviders, near: anchor)
    }

    func present(result: TranslationResult, source: String?, viaFallback: Bool) {
        if result.operation == .screenTranslate, settingsStore.autoCopyOCR {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(result.translated, forType: .string)
        }
        popup.state.setResult(result)
        popup.state.availableRetryProviders = retryProviders(excluding: result.provider, for: result.operation)
        statusController.apply(.idle)
        let entry = TranslationHistoryEntry(
            original: result.original,
            translated: result.translated,
            sourceLanguage: source,
            targetLanguage: result.targetLanguage,
            provider: result.provider,
            operation: result.operation
        )
        historyStore.add(entry, maxCount: settingsStore.maxHistoryCount)
    }

    // MARK: - Provider availability

    func retryProviders(excluding: ProviderType, for operation: AIOperation) -> [ProviderType] {
        ProviderType.allCases.filter { type in
            guard type != excluding, isProviderReady(type, for: operation) else { return false }
            if operation == .screenTranslate {
                return translationService.providers[type]?.supportsVision == true
            }
            return true
        }
    }

    func visionCapableProviders(excluding: ProviderType? = nil) -> [ProviderType] {
        ProviderType.allCases.filter { type in
            guard type != excluding else { return false }
            guard let impl = translationService.providers[type] else { return false }
            guard impl.supportsVision else { return false }
            if impl.requiresApiKey { return settingsStore.hasApiKey(for: type) }
            return true
        }
    }

    func translateProviders() -> [ProviderType] {
        ProviderType.allCases.filter { isProviderReady($0, for: .screenTranslate) }
    }

    private func isProviderReady(_ provider: ProviderType, for operation: AIOperation) -> Bool {
        guard let impl = translationService.providers[provider] else { return false }
        guard impl.supportedOperations.contains(operation) else { return false }
        if !impl.requiresApiKey { return true }
        return settingsStore.hasApiKey(for: provider)
    }
}
