import Foundation
import Combine

@MainActor
final class PopupState: ObservableObject {

    enum Phase {
        case loading(originalPreview: String)
        case result(TranslationResult)
        case error(String)
    }

    @Published var phase: Phase = .loading(originalPreview: "")
    @Published var availableRetryProviders: [ProviderType] = []
    var onRetry: ((ProviderType) -> Void)?
    var onReplace: ((String) -> Void)?
    var onRetranslate: ((String) -> Void)?

    func setLoading(original: String) {
        phase = .loading(originalPreview: String(original.prefix(120)))
    }

    func setResult(_ result: TranslationResult) {
        phase = .result(result)
    }

    func setError(_ message: String) {
        phase = .error(message)
    }
}
