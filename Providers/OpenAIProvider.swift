import Foundation

struct OpenAIProvider: AIProvider {

    let type: ProviderType = .openai
    let defaultBaseURL = "https://api.openai.com"
    let availableModels = [
        "gpt-5.6-luna",
        "gpt-5.6-terra",
        "gpt-5.6-sol",
        "gpt-5.5-pro",
        "gpt-5.5",
        "gpt-5.4",
        "gpt-5.4-mini",
        "gpt-5.4-nano",
        "gpt-4.1",
        "gpt-4.1-mini"
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
        let usage: Usage?
        struct Choice: Decodable {
            let message: Message
            let finish_reason: String?
            struct Message: Decodable {
                let content: String?
            }
        }
        struct Usage: Decodable {
            let prompt_tokens: Int
            let completion_tokens: Int
        }
    }

    var supportsVision: Bool { true }

    private static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        return URLSession(configuration: config)
    }()

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

    func executeVision(image: Data, targetLanguage: String, config: ProviderConfig) async throws -> ProviderResult {
        guard !config.apiKey.isEmpty else { throw TranslationError.missingApiKey }
        let base = config.baseURL.isEmpty ? defaultBaseURL : config.baseURL
        guard let schemeURL = URL(string: base), schemeURL.scheme == "https" else {
            throw TranslationError.invalidConfiguration("baseURL must use HTTPS scheme")
        }
        guard let url = URL(string: base.trimmingCharacters(in: ["/"]) + "/v1/chat/completions") else {
            throw TranslationError.invalidURL
        }

        let base64 = image.base64EncodedString()
        let dataURI = "data:image/jpeg;base64,\(base64)"
        let prompt = PromptBuilder.visionPrompt(targetLanguage: targetLanguage)

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

        let data = try await performRequest(request, session: Self.session)

        do {
            let decoded = try JSONDecoder().decode(ResponseBody.self, from: data)
            guard var text = decoded.choices.first?.message.content?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !text.isEmpty else { throw TranslationError.emptyResponse }
            if decoded.choices.first?.finish_reason == "length" {
                text += "\n\n⚠️ Response was truncated (max tokens reached)"
            }
            let usage = decoded.usage.map { TokenUsage(inputTokens: $0.prompt_tokens, outputTokens: $0.completion_tokens) }
            return ProviderResult(text: text, usage: usage)
        } catch let error as TranslationError {
            throw error
        } catch {
            throw TranslationError.decoding(error.localizedDescription)
        }
    }

    func execute(text: String, operation: AIOperation, config: ProviderConfig) async throws -> ProviderResult {
        guard !config.apiKey.isEmpty else { throw TranslationError.missingApiKey }
        let base = config.baseURL.isEmpty ? defaultBaseURL : config.baseURL
        guard let schemeURL = URL(string: base), schemeURL.scheme == "https" else {
            throw TranslationError.invalidConfiguration("baseURL must use HTTPS scheme")
        }
        guard let url = URL(string: base.trimmingCharacters(in: ["/"]) + "/v1/chat/completions") else {
            throw TranslationError.invalidURL
        }

        let body = RequestBody(
            model: config.model,
            messages: [
                .init(role: "system", content: PromptBuilder.systemPrompt(for: operation, targetLanguage: config.targetLanguage, magicPrompt: config.magicPrompt)),
                .init(role: "user", content: PromptBuilder.userContent(text))
            ],
            temperature: 0.3
        )

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(body)

        let data = try await performRequest(request, session: Self.session)

        do {
            let decoded = try JSONDecoder().decode(ResponseBody.self, from: data)
            guard var text = decoded.choices.first?.message.content?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !text.isEmpty else { throw TranslationError.emptyResponse }
            if decoded.choices.first?.finish_reason == "length" {
                text += "\n\n⚠️ Response was truncated (max tokens reached)"
            }
            let usage = decoded.usage.map { TokenUsage(inputTokens: $0.prompt_tokens, outputTokens: $0.completion_tokens) }
            return ProviderResult(text: text, usage: usage)
        } catch let error as TranslationError {
            throw error
        } catch {
            throw TranslationError.decoding(error.localizedDescription)
        }
    }
}
