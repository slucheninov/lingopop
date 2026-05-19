import Foundation

struct DeepLProvider: AIProvider {

    let type: ProviderType = .deepl
    let defaultBaseURL = "https://api-free.deepl.com"
    let availableModels: [String] = []
    let supportedOperations: Set<AIOperation> = [.translate]

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

    func execute(text: String, operation: AIOperation, config: ProviderConfig) async throws -> String {
        guard operation == .translate else {
            throw TranslationError.operationNotSupported(provider: type, operation: operation)
        }
        guard !config.apiKey.isEmpty else { throw TranslationError.missingApiKey }
        let base = config.baseURL.isEmpty ? defaultBaseURL : config.baseURL
        guard let url = URL(string: base.trimmingCharacters(in: ["/"]) + "/v2/translate") else {
            throw TranslationError.invalidURL
        }

        let body = RequestBody(
            text: [PromptBuilder.userContent(text)],
            target_lang: LanguageCodes.deepLCode(for: config.targetLanguage)
        )

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("DeepL-Auth-Key \(config.apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw TranslationError.network(error)
        }
        guard let http = response as? HTTPURLResponse else {
            throw TranslationError.decoding("Not an HTTP response")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw TranslationError.http(status: http.statusCode, body: String(data: data, encoding: .utf8) ?? "", url: url.absoluteString)
        }

        do {
            let decoded = try JSONDecoder().decode(ResponseBody.self, from: data)
            guard let translated = decoded.translations.first?.text, !translated.isEmpty else {
                throw TranslationError.emptyResponse
            }
            return translated.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch let error as TranslationError {
            throw error
        } catch {
            throw TranslationError.decoding(error.localizedDescription)
        }
    }
}
