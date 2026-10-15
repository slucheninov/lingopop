import Foundation
import Combine

struct PopupError: Equatable {
    let message: String
    let details: String?

    init(message: String, details: String? = nil) {
        self.message = message
        self.details = details
    }

    init(_ error: TranslationError) {
        message = error.userSummary
        details = error.technicalDetails
    }
}

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
    var onRetry: ((ProviderType) -> Void)?
    var onReplace: ((String) -> Void)?
    var onRetranslate: ((String) -> Void)?
    var onRewrite: ((String) -> Void)?
    var onExplain: ((String) -> Void)?
    var onTranslate: ((String, ProviderType) -> Void)?

    func setLoading(operation: AIOperation, original: String) {
        availableRetryProviders = []
        phase = .loading(operation: operation, originalPreview: String(original.prefix(120)))
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

    func setError(_ message: String) {
        setError(PopupError(message: message))
    }

    func setError(_ error: TranslationError) {
        setError(PopupError(error))
    }
}
