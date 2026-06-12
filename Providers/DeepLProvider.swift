import Foundation

struct DeepLProvider: AIProvider {

    let type: ProviderType = .deepl
    let defaultBaseURL = "https://api.deepl.com"
    let availableModels: [String] = []
    let supportedOperations: Set<AIOperation> = [.translate, .screenTranslate]

    private struct RequestBody: Encodable {
        let text: [String]
        let target_lang: String
    }

    private static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        return URLSession(configuration: config)
    }()

    private struct ResponseBody: Decodable {
        let translations: [Translation]
        struct Translation: Decodable {
            let text: String
        }
    }

    func execute(text: String, operation: AIOperation, config: ProviderConfig) async throws -> ProviderResult {
        guard operation == .translate || operation == .screenTranslate else {
            throw TranslationError.operationNotSupported(provider: type, operation: operation)
        }
        guard !config.apiKey.isEmpty else { throw TranslationError.missingApiKey }
        let base: String
        if config.baseURL.isEmpty {
            base = config.apiKey.hasSuffix(":fx") ? "https://api-free.deepl.com" : "https://api.deepl.com"
        } else {
            base = config.baseURL
        }
        guard let schemeURL = URL(string: base), schemeURL.scheme == "https" else {
            throw TranslationError.invalidConfiguration("baseURL must use HTTPS scheme")
        }
        guard let url = URL(string: base.trimmingCharacters(in: ["/"]) + "/v2/translate") else {
            throw TranslationError.invalidURL
        }

        let body = RequestBody(
            text: [text],
            target_lang: LanguageCodes.deepLCode(for: config.targetLanguage)
        )

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("DeepL-Auth-Key \(config.apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(body)

        let data = try await performRequest(request, session: Self.session)

        do {
            let decoded = try JSONDecoder().decode(ResponseBody.self, from: data)
            guard let translated = decoded.translations.first?.text, !translated.isEmpty else {
                throw TranslationError.emptyResponse
            }
            return ProviderResult(text: translated.trimmingCharacters(in: .whitespacesAndNewlines), usage: nil)
        } catch let error as TranslationError {
            throw error
        } catch {
            throw TranslationError.decoding(error.localizedDescription)
        }
    }
}
