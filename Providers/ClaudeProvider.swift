import Foundation

struct ClaudeProvider: AIProvider {

    let type: ProviderType = .claude
    let defaultBaseURL = "https://api.anthropic.com"
    let availableModels = [
        "claude-haiku-4-5",
        "claude-sonnet-4-6",
        "claude-opus-4-7"
    ]

    private struct RequestBody: Encodable {
        let model: String
        let max_tokens: Int
        let system: String
        let messages: [Message]
        struct Message: Encodable {
            let role: String
            let content: String
        }
    }

    private struct ResponseBody: Decodable {
        let content: [ContentBlock]
        struct ContentBlock: Decodable {
            let type: String
            let text: String?
        }
    }

    func execute(text: String, operation: AIOperation, config: ProviderConfig) async throws -> String {
        guard !config.apiKey.isEmpty else { throw TranslationError.missingApiKey }
        let base = config.baseURL.isEmpty ? defaultBaseURL : config.baseURL
        guard let url = URL(string: base.trimmingCharacters(in: ["/"]) + "/v1/messages") else {
            throw TranslationError.invalidURL
        }

        let body = RequestBody(
            model: config.model,
            max_tokens: 2048,
            system: PromptBuilder.systemPrompt(for: operation, targetLanguage: config.targetLanguage),
            messages: [.init(role: "user", content: text)]
        )

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(config.apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
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
            let text = decoded.content.compactMap { $0.text }.joined()
            guard !text.isEmpty else { throw TranslationError.emptyResponse }
            return text
        } catch let error as TranslationError {
            throw error
        } catch {
            throw TranslationError.decoding(error.localizedDescription)
        }
    }
}
