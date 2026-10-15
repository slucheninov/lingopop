import Foundation

struct GeminiProvider: AIProvider {

    let type: ProviderType = .gemini
    let defaultBaseURL = "https://generativelanguage.googleapis.com"
    let availableModels = [
        "gemini-4-argon",
        "gemini-3.8-flash",
        "gemini-3.6-flash",
        "gemini-3.5-flash-lite",
        "gemini-3.1-pro-preview",
        "gemini-3.1-flash-lite",
        "gemini-2.5-flash-lite",
        "gemini-2.5-flash",
        "gemini-2.5-pro"
    ]

    private struct RequestBody: Encodable {
        let systemInstruction: Instruction?
        let contents: [Content]

        struct Instruction: Encodable {
            let parts: [Part]
        }
        struct Content: Encodable {
            let role: String
            let parts: [Part]
        }
        enum Part: Encodable {
            case text(String)
            case inlineData(mimeType: String, data: String)

            func encode(to encoder: Encoder) throws {
                var c = encoder.container(keyedBy: CodingKeys.self)
                switch self {
                case .text(let t):
                    try c.encode(t, forKey: .text)
                case .inlineData(let mime, let data):
                    try c.encode(InlineData(mimeType: mime, data: data), forKey: .inlineData)
                }
            }

            enum CodingKeys: String, CodingKey { case text, inlineData }
            struct InlineData: Encodable {
                let mimeType: String
                let data: String
            }
        }
    }

    private struct ResponseBody: Decodable {
        let candidates: [Candidate]
        let usageMetadata: UsageMetadata?
        struct Candidate: Decodable {
            let content: Content?
            let finishReason: String?
            struct Content: Decodable {
                let parts: [Part]?
                struct Part: Decodable {
                    let text: String?
                }
            }
        }
        struct UsageMetadata: Decodable {
            let promptTokenCount: Int
            let candidatesTokenCount: Int?
        }
    }

    var supportsVision: Bool { true }

    func executeVision(image: Data, targetLanguage: String, config: ProviderConfig) async throws -> ProviderResult {
        guard !config.apiKey.isEmpty else { throw TranslationError.missingApiKey }
        return try await send(
            system: nil,
            parts: [
                .inlineData(mimeType: mimeType(for: image), data: image.base64EncodedString()),
                .text(PromptBuilder.visionPrompt(targetLanguage: targetLanguage))
            ],
            config: config,
            sanitize: false
        )
    }

    func execute(text: String, operation: AIOperation, config: ProviderConfig) async throws -> ProviderResult {
        try await send(
            system: PromptBuilder.systemPrompt(for: operation, targetLanguage: config.targetLanguage, magicPrompt: config.magicPrompt),
            parts: [.text(PromptBuilder.userContent(text))],
            config: config,
            sanitize: true
        )
    }

    private func send(
        system: String?,
        parts: [RequestBody.Part],
        config: ProviderConfig,
        sanitize: Bool
    ) async throws -> ProviderResult {
        guard config.model.range(of: "^[A-Za-z0-9][A-Za-z0-9._-]*$", options: .regularExpression) != nil else {
            throw TranslationError.invalidConfiguration("Gemini model name is empty or contains unsupported characters")
        }
        let url = try ProviderHTTP.endpoint(
            baseURL: config.baseURL,
            defaultBaseURL: defaultBaseURL,
            path: "/v1beta/models/\(config.model):generateContent"
        )
        let body = RequestBody(
            systemInstruction: system.map { RequestBody.Instruction(parts: [.text($0)]) },
            contents: [.init(role: "user", parts: parts)]
        )
        let request = try ProviderHTTP.jsonRequest(
            url: url,
            headers: ["x-goog-api-key": config.apiKey],
            body: body
        )
        let data = try await ProviderHTTP.perform(request)
        let decoded = try ProviderHTTP.decode(ResponseBody.self, from: data)

        let raw = decoded.candidates
            .compactMap { $0.content?.parts?.compactMap { $0.text }.joined() }
            .joined()
        let text = sanitize ? PromptBuilder.sanitizeOutput(raw) : raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw TranslationError.emptyResponse }
        let usage = decoded.usageMetadata.map {
            TokenUsage(inputTokens: $0.promptTokenCount, outputTokens: $0.candidatesTokenCount ?? 0)
        }
        return ProviderResult(text: text, usage: usage, truncated: decoded.candidates.first?.finishReason == "MAX_TOKENS")
    }
}
