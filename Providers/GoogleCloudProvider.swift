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

    func execute(text: String, operation: AIOperation, config: ProviderConfig) async throws -> String {
        guard operation == .translate || operation == .screenTranslate else {
            throw TranslationError.operationNotSupported(provider: type, operation: operation)
        }
        guard !config.apiKey.isEmpty else { throw TranslationError.missingApiKey }
        let base = config.baseURL.isEmpty ? defaultBaseURL : config.baseURL
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
            guard let translated = decoded.data.translations.first?.translatedText, !translated.isEmpty else {
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
