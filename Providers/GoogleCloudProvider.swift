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
        let url = try ProviderHTTP.endpoint(
            baseURL: config.baseURL,
            defaultBaseURL: defaultBaseURL,
            path: "/language/translate/v2",
            query: [URLQueryItem(name: "key", value: config.apiKey)]
        )

        let body = RequestBody(
            q: text,
            target: LanguageCodes.code(for: config.targetLanguage),
            model: config.model.isEmpty ? nil : config.model,
            format: "text"
        )

        var headers: [String: String] = [:]
        if let referer = config.referer, !referer.isEmpty {
            headers["Referer"] = referer
        }
        let request = try ProviderHTTP.jsonRequest(url: url, headers: headers, body: body)

        let data = try await ProviderHTTP.perform(request)

        let decoded = try ProviderHTTP.decode(ResponseBody.self, from: data)
        guard let translated = decoded.data.translations.first?.translatedText, !translated.isEmpty else {
            throw TranslationError.emptyResponse
        }
        return ProviderResult(text: translated.trimmingCharacters(in: .whitespacesAndNewlines), usage: nil)
    }
}
