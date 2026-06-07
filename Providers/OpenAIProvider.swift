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

    var supportsVision: Bool { true }

    private struct VisionRequestBody: Encodable {
        let model: String
        let messages: [VisionMessage]
        let temperature: Double

        struct VisionMessage: Encodable {
            let role: String
            let content: [Part]

            enum Part: Encodable {
                case text(String)
                case imageURL(String)

                func encode(to encoder: Encoder) throws {
                    var c = encoder.container(keyedBy: CodingKeys.self)
                    switch self {
                    case .text(let t):
                        try c.encode("text", forKey: .type)
                        try c.encode(t, forKey: .text)
                    case .imageURL(let url):
                        try c.encode("image_url", forKey: .type)
                        try c.encode(ImageURL(url: url), forKey: .image_url)
                    }
                }

                enum CodingKeys: String, CodingKey { case type, text, image_url }
                struct ImageURL: Encodable { let url: String }
            }
        }
    }

    func executeVision(image: Data, targetLanguage: String, config: ProviderConfig) async throws -> String {
        guard !config.apiKey.isEmpty else { throw TranslationError.missingApiKey }
        let base = config.baseURL.isEmpty ? defaultBaseURL : config.baseURL
        guard let url = URL(string: base.trimmingCharacters(in: ["/"]) + "/v1/chat/completions") else {
            throw TranslationError.invalidURL
        }

        let base64 = image.base64EncodedString()
        let dataURI = "data:image/jpeg;base64,\(base64)"
        let prompt = "Extract all text from this image and translate it into \(targetLanguage). Output only the translated text. No explanations, no preamble."

        let body = VisionRequestBody(
            model: config.model,
            messages: [.init(role: "user", content: [
                .imageURL(dataURI),
                .text(prompt)
            ])],
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
