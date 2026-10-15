import Foundation

struct DeepLProvider: AIProvider {

    let type: ProviderType = .deepl
    let defaultBaseURL = "https://api.deepl.com"
    let availableModels: [String] = []
    let autoBaseURL = true
    let supportedOperations: Set<AIOperation> = [.translate, .screenTranslate]

    private struct RequestBody: Encodable {
        let text: [String]
        let target_lang: String
    }

    private struct ResponseBody: Decodable {
        let translations: [Translation]
        struct Translation: Decodable {
            let text: String
        }
    }

    func execute(text: String, operation: AIOperation, config: ProviderConfig) async throws -> ProviderResult {
        let effectiveBase = config.baseURL.isEmpty
            ? (config.apiKey.hasSuffix(":fx") ? "https://api-free.deepl.com" : defaultBaseURL)
            : config.baseURL
        let url = try ProviderHTTP.endpoint(baseURL: effectiveBase, defaultBaseURL: defaultBaseURL, path: "/v2/translate")

        let body = RequestBody(
            text: [text],
            target_lang: LanguageCodes.deepLCode(for: config.targetLanguage)
        )
        let request = try ProviderHTTP.jsonRequest(
            url: url,
            headers: ["Authorization": "DeepL-Auth-Key \(config.apiKey)"],
            body: body
        )

        let data = try await ProviderHTTP.perform(request)

        let decoded = try ProviderHTTP.decode(ResponseBody.self, from: data)
        guard let translated = decoded.translations.first?.text, !translated.isEmpty else {
            throw TranslationError.emptyResponse
        }
        return ProviderResult(text: translated.trimmingCharacters(in: .whitespacesAndNewlines), usage: nil)
    }
}
