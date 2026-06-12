import Foundation

struct MicrosoftTranslatorProvider: AIProvider {

    let type: ProviderType = .microsoftTranslator
    let defaultBaseURL = "https://api.cognitive.microsofttranslator.com"
    let availableModels: [String] = []
    let supportedOperations: Set<AIOperation> = [.translate, .screenTranslate]

    private struct RequestItem: Encodable {
        let Text: String
    }

    private static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        return URLSession(configuration: config)
    }()

    private struct ResponseItem: Decodable {
        let translations: [Translation]
        struct Translation: Decodable {
            let text: String
            let to: String
        }
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
        let targetCode = LanguageCodes.code(for: config.targetLanguage)
        var components = URLComponents(string: base.trimmingCharacters(in: ["/"]) + "/translate")
        components?.queryItems = [
            URLQueryItem(name: "api-version", value: "3.0"),
            URLQueryItem(name: "to", value: targetCode)
        ]
        guard let url = components?.url else {
            throw TranslationError.invalidURL
        }

        let body = [RequestItem(Text: text)]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(config.apiKey, forHTTPHeaderField: "Ocp-Apim-Subscription-Key")
        if let region = config.region, !region.isEmpty {
            request.setValue(region, forHTTPHeaderField: "Ocp-Apim-Subscription-Region")
        }
        request.httpBody = try JSONEncoder().encode(body)

        let data = try await performRequest(request, session: Self.session)

        do {
            let decoded = try JSONDecoder().decode([ResponseItem].self, from: data)
            guard let translated = decoded.first?.translations.first?.text, !translated.isEmpty else {
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
