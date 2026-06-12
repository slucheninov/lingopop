import Foundation

struct GoogleCloudProvider: AIProvider {

    let type: ProviderType = .googleCloud
    let defaultBaseURL = "https://translation.googleapis.com"
    let availableModels: [String] = ["nmt", "base"]
    let requiresApiKey: Bool = true
    let supportedOperations: Set<AIOperation> = [.translate, .screenTranslate]

    private struct RequestBody: Encodable {
        let q: String
        let target: String
        let model: String?
        let format: String
    }

    private static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        return URLSession(configuration: config)
    }()

    private struct ResponseBody: Decodable {
        struct DataField: Decodable {
            struct Translation: Decodable {
                let translatedText: String
            }
            let translations: [Translation]
        }
        let data: DataField
    }

    func execute(text: String, operation: AIOperation, config: ProviderConfig) async throws -> ProviderResult {
        guard operation == .translate || operation == .screenTranslate else {
            throw TranslationError.operationNotSupported(provider: type, operation: operation)
        }
        guard !config.apiKey.isEmpty else { throw TranslationError.missingApiKey }
        let base = config.baseURL.isEmpty ? defaultBaseURL : config.baseURL
        guard let schemeURL = URL(string: base), schemeURL.scheme == "https" else {
            throw TranslationError.invalidConfiguration("baseURL must use HTTPS scheme")
        }
        let target = LanguageCodes.code(for: config.targetLanguage)

        var components = URLComponents(string: base.trimmingCharacters(in: ["/"]) + "/language/translate/v2")
        components?.queryItems = [URLQueryItem(name: "key", value: config.apiKey)]
        guard let url = components?.url else {
            throw TranslationError.invalidURL
        }

        let body = RequestBody(
            q: text,
            target: target,
            model: config.model.isEmpty ? nil : config.model,
            format: "text"
        )

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let referer = config.referer, !referer.isEmpty {
            request.setValue(referer, forHTTPHeaderField: "Referer")
        }
        request.httpBody = try JSONEncoder().encode(body)

        let data = try await performRequest(request, session: Self.session)

        do {
            let decoded = try JSONDecoder().decode(ResponseBody.self, from: data)
            guard let translated = decoded.data.translations.first?.translatedText, !translated.isEmpty else {
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
