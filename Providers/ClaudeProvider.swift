import Foundation

struct ClaudeProvider: AIProvider {

    let type: ProviderType = .claude
    let defaultBaseURL = "https://api.anthropic.com"
    let availableModels = [
        "claude-fable-5-1",
        "claude-opus-5-5",
        "claude-sonnet-5-5",
        "claude-haiku-5-5",
        "claude-fable-5",
        "claude-opus-5",
        "claude-opus-4-8",
        "claude-sonnet-5",
        "claude-sonnet-4-6",
        "claude-opus-4-7"
    ]

    private struct RequestBody: Encodable {
        let model: String
        let max_tokens: Int
        let system: String?
        let messages: [Message]

        struct Message: Encodable {
            let role: String
            let content: [Block]
        }

        enum Block: Encodable {
            case text(String)
            case image(base64: String, mediaType: String)

            func encode(to encoder: Encoder) throws {
                var c = encoder.container(keyedBy: CodingKeys.self)
                switch self {
                case .text(let t):
                    try c.encode("text", forKey: .type)
                    try c.encode(t, forKey: .text)
                case .image(let b64, let mime):
                    try c.encode("image", forKey: .type)
                    try c.encode(Source(type: "base64", media_type: mime, data: b64), forKey: .source)
                }
            }

            enum CodingKeys: String, CodingKey { case type, text, source }

            struct Source: Encodable {
                let type: String
                let media_type: String
                let data: String
            }
        }
    }

    private struct ResponseBody: Decodable {
        let content: [ContentBlock]
        let stop_reason: String?
        let usage: Usage?
        struct ContentBlock: Decodable {
            let type: String
            let text: String?
        }
        struct Usage: Decodable {
            let input_tokens: Int
            let output_tokens: Int
        }
    }

    var supportsVision: Bool { true }

    private let anthropicAPIVersion = "2023-06-01"

    func executeVision(image: Data, targetLanguage: String, config: ProviderConfig) async throws -> ProviderResult {
        guard !config.apiKey.isEmpty else { throw TranslationError.missingApiKey }
        return try await send(
            system: nil,
            content: [
                .image(base64: image.base64EncodedString(), mediaType: mimeType(for: image)),
                .text(PromptBuilder.visionPrompt(targetLanguage: targetLanguage))
            ],
            config: config,
            sanitize: false
        )
    }

    func execute(text: String, operation: AIOperation, config: ProviderConfig) async throws -> ProviderResult {
        try await send(
            system: PromptBuilder.systemPrompt(for: operation, targetLanguage: config.targetLanguage, magicPrompt: config.magicPrompt),
            content: [.text(PromptBuilder.userContent(text))],
            config: config,
            sanitize: true
        )
    }

    private func send(
        system: String?,
        content: [RequestBody.Block],
        config: ProviderConfig,
        sanitize: Bool
    ) async throws -> ProviderResult {
        let url = try ProviderHTTP.endpoint(baseURL: config.baseURL, defaultBaseURL: defaultBaseURL, path: "/v1/messages")
        let body = RequestBody(
            model: config.model,
            max_tokens: 4096,
            system: system,
            messages: [.init(role: "user", content: content)]
        )
        let request = try ProviderHTTP.jsonRequest(
            url: url,
            headers: ["x-api-key": config.apiKey, "anthropic-version": anthropicAPIVersion],
            body: body
        )
        let data = try await ProviderHTTP.perform(request)
        let decoded = try ProviderHTTP.decode(ResponseBody.self, from: data)

        let raw = decoded.content.compactMap { $0.text }.joined()
        let text = sanitize ? PromptBuilder.sanitizeOutput(raw) : raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw TranslationError.emptyResponse }
        let usage = decoded.usage.map { TokenUsage(inputTokens: $0.input_tokens, outputTokens: $0.output_tokens) }
        return ProviderResult(text: text, usage: usage, truncated: decoded.stop_reason == "max_tokens")
    }
}
