import Foundation

struct OpenAIProvider: AIProvider {

    let type: ProviderType
    let defaultBaseURL: String
    let availableModels: [String]

    init(
        type: ProviderType = .openai,
        defaultBaseURL: String = "https://api.openai.com",
        availableModels: [String] = OpenAIProvider.openAIModels
    ) {
        self.type = type
        self.defaultBaseURL = defaultBaseURL
        self.availableModels = availableModels
    }

    static let openAIModels = [
        "gpt-6-astra",
        "gpt-6.1-sol",
        "gpt-6-luna",
        "gpt-5.6-luna",
        "gpt-5.6-terra",
        "gpt-5.6-sol",
        "gpt-5.5-pro",
        "gpt-5.5",
        "gpt-5.4",
        "gpt-5.4-mini"
    ]

    private struct RequestBody: Encodable {
        let model: String
        let messages: [Message]

        struct Message: Encodable {
            let role: String
            let content: Content
        }

        enum Content: Encodable {
            case text(String)
            case parts([Part])

            func encode(to encoder: Encoder) throws {
                var c = encoder.singleValueContainer()
                switch self {
                case .text(let t): try c.encode(t)
                case .parts(let p): try c.encode(p)
                }
            }
        }

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

    func executeVision(image: Data, targetLanguage: String, config: ProviderConfig) async throws -> ProviderResult {
        guard !config.apiKey.isEmpty else { throw TranslationError.missingApiKey }
        let dataURI = "data:\(mimeType(for: image));base64,\(image.base64EncodedString())"
        return try await send(
            messages: [.init(role: "user", content: .parts([
                .imageURL(dataURI),
                .text(PromptBuilder.visionPrompt(targetLanguage: targetLanguage))
            ]))],
            config: config,
            sanitize: false
        )
    }

    func execute(text: String, operation: AIOperation, config: ProviderConfig) async throws -> ProviderResult {
        try await send(
            messages: [
                .init(role: "system", content: .text(PromptBuilder.systemPrompt(for: operation, targetLanguage: config.targetLanguage, magicPrompt: config.magicPrompt))),
                .init(role: "user", content: .text(PromptBuilder.userContent(text)))
            ],
            config: config,
            sanitize: true
        )
    }

    private func send(
        messages: [RequestBody.Message],
        config: ProviderConfig,
        sanitize: Bool
    ) async throws -> ProviderResult {
        let url = try ProviderHTTP.endpoint(baseURL: config.baseURL, defaultBaseURL: defaultBaseURL, path: "/v1/chat/completions")
        let request = try ProviderHTTP.jsonRequest(
            url: url,
            headers: ["Authorization": "Bearer \(config.apiKey)"],
            body: RequestBody(model: config.model, messages: messages)
        )
        let data = try await ProviderHTTP.perform(request)
        let decoded = try ProviderHTTP.decode(ResponseBody.self, from: data)

        guard let choice = decoded.choices.first, let raw = choice.message.content else {
            throw TranslationError.emptyResponse
        }
        let text = sanitize ? PromptBuilder.sanitizeOutput(raw) : raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw TranslationError.emptyResponse }
        let usage = decoded.usage.map { TokenUsage(inputTokens: $0.prompt_tokens, outputTokens: $0.completion_tokens) }
        return ProviderResult(text: text, usage: usage, truncated: choice.finish_reason == "length")
    }
}
