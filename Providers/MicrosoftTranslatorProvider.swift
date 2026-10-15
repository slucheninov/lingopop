import Foundation

struct MicrosoftTranslatorProvider: AIProvider {

    let type: ProviderType = .microsoftTranslator
    let defaultBaseURL = "https://api.cognitive.microsofttranslator.com"
    let availableModels: [String] = []
    let supportedOperations: Set<AIOperation> = [.translate, .screenTranslate]

    private struct RequestItem: Encodable {
        let Text: String
    }

    private struct ResponseItem: Decodable {
        let translations: [Translation]
        struct Translation: Decodable {
            let text: String
            let to: String
        }
    }

    func execute(text: String, operation: AIOperation, config: ProviderConfig) async throws -> ProviderResult {
        let url = try ProviderHTTP.endpoint(
            baseURL: config.baseURL,
            defaultBaseURL: defaultBaseURL,
            path: "/translate",
            query: [
                URLQueryItem(name: "api-version", value: "3.0"),
                URLQueryItem(name: "to", value: LanguageCodes.microsoftCode(for: config.targetLanguage))
            ]
        )

        var headers = ["Ocp-Apim-Subscription-Key": config.apiKey]
        if let region = config.region, !region.isEmpty {
            headers["Ocp-Apim-Subscription-Region"] = region
        }
        let request = try ProviderHTTP.jsonRequest(url: url, headers: headers, body: [RequestItem(Text: text)])

        let data = try await ProviderHTTP.perform(request)

        let decoded = try ProviderHTTP.decode([ResponseItem].self, from: data)
        guard let translated = decoded.first?.translations.first?.text, !translated.isEmpty else {
            throw TranslationError.emptyResponse
        }
        return ProviderResult(text: translated.trimmingCharacters(in: .whitespacesAndNewlines), usage: nil)
    }
}
