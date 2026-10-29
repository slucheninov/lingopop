import Foundation
import Combine

@MainActor
final class PopupState: ObservableObject {

    enum Phase {
        case loading(operation: AIOperation, originalPreview: String)
        case ocr(text: String)
        case result(TranslationResult)
        case error(PopupError)
    }

    @Published var phase: Phase = .loading(operation: .translate, originalPreview: "")
    @Published var availableRetryProviders: [ProviderType] = []
    @Published var availableTranslateProviders: [ProviderType] = []
    @Published var activeTranslateProvider: ProviderType? = nil

    /// Weak: the actions object (AppDelegate) owns the popup, not the other way round.
    private(set) weak var actions: PopupActions?

    init(actions: PopupActions) {
        self.actions = actions
    }

    func setLoading(operation: AIOperation, original: String) {
        availableRetryProviders = []
        phase = .loading(operation: operation, originalPreview: String(original.prefix(PopupLayout.previewCharacterLimit)))
    }

    func setOCR(_ text: String) {
        phase = .ocr(text: text)
    }

    func setResult(_ result: TranslationResult) {
        phase = .result(result)
    }

    func setError(_ error: PopupError) {
        availableRetryProviders = []
        phase = .error(error)
    }

    /// Maps any error through `PopupError.from`. Cancellation is never presented.
    func setError(_ error: Error) {
        guard !(error is CancellationError) else { return }
        setError(PopupError.from(error))
    }
}
