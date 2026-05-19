import Foundation
import Combine

@MainActor
final class PopupState: ObservableObject {

    enum Phase {
        case loading(operation: AIOperation, originalPreview: String)
        case result(TranslationResult)
        case error(String)
    }

    @Published var phase: Phase = .loading(operation: .translate, originalPreview: "")
    @Published var availableRetryProviders: [ProviderType] = []
    var onRetry: ((ProviderType) -> Void)?
    var onReplace: ((String) -> Void)?
    var onRetranslate: ((String) -> Void)?
    var onRewrite: ((String) -> Void)?

    func setLoading(operation: AIOperation, original: String) {
        phase = .loading(operation: operation, originalPreview: String(original.prefix(120)))
    }

    func setResult(_ result: TranslationResult) {
        phase = .result(result)
    }

    func setError(_ message: String) {
        phase = .error(message)
    }
}
