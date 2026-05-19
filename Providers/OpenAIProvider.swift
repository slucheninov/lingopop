import Foundation

struct OpenAIProvider: AIProvider {

    let type: ProviderType = .openai
    let defaultBaseURL = "https://api.openai.com"
    let availableModels = [
        "gpt-5.4-nano",
        "gpt-5.4-mini",
        "gpt-5.4",
        "gpt-5.5"
    ]

    private struct RequestBody: Encodable {
        let model: String
        let messages: [Message]
        let temperature: Double
        struct Message: Encodable {
            let role: String
            let content: String
        }
    }

    private struct ResponseBody: Decodable {
        let choices: [Choice]
        struct Choice: Decodable {
            let message: Message
            struct Message: Decodable {
                let content: String?
            }
        }
    }

    func execute(text: String, operation: AIOperation, config: ProviderConfig) async throws -> String {
        guard !config.apiKey.isEmpty else { throw TranslationError.missingApiKey }
        let base = config.baseURL.isEmpty ? defaultBaseURL : config.baseURL
        guard let url = URL(string: base.trimmingCharacters(in: ["/"]) + "/v1/chat/completions") else {
            throw TranslationError.invalidURL
        }

        let body = RequestBody(
            model: config.model,
            messages: [
                .init(role: "system", content: PromptBuilder.systemPrompt(for: operation, targetLanguage: config.targetLanguage)),
                .init(role: "user", content: PromptBuilder.userContent(text))
            ],
            temperature: 0.3
        )

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
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
            guard let text = decoded.choices.first?.message.content, !text.isEmpty else {
                throw TranslationError.emptyResponse
            }
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch let error as TranslationError {
            throw error
        } catch {
            throw TranslationError.decoding(error.localizedDescription)
        }
    }
}
