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

    private static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        return URLSession(configuration: config)
    }()

    private struct VisionRequestBody: Encodable {
        let model: String
        let max_tokens: Int
        let messages: [VisionMessage]

        struct VisionMessage: Encodable {
            let role: String
            let content: [Block]

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
    }

    func executeVision(image: Data, targetLanguage: String, config: ProviderConfig) async throws -> ProviderResult {
        guard !config.apiKey.isEmpty else { throw TranslationError.missingApiKey }
        let base = config.baseURL.isEmpty ? defaultBaseURL : config.baseURL
        guard let schemeURL = URL(string: base), schemeURL.scheme == "https" else {
            throw TranslationError.invalidConfiguration("baseURL must use HTTPS scheme")
        }
        guard let url = URL(string: base.trimmingCharacters(in: ["/"]) + "/v1/messages") else {
            throw TranslationError.invalidURL
        }

        let base64 = image.base64EncodedString()
        let prompt = PromptBuilder.visionPrompt(targetLanguage: targetLanguage)

        let body = VisionRequestBody(
            model: config.model,
            max_tokens: 4096,
            messages: [.init(role: "user", content: [
                .image(base64: base64, mediaType: mimeType(for: image)),
                .text(prompt)
            ])]
        )

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(config.apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(anthropicAPIVersion, forHTTPHeaderField: "anthropic-version")
        request.httpBody = try JSONEncoder().encode(body)

        let data = try await performRequest(request, session: Self.session)

        do {
            let decoded = try JSONDecoder().decode(ResponseBody.self, from: data)
            var text = decoded.content.compactMap { $0.text }.joined()
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { throw TranslationError.emptyResponse }
            if decoded.stop_reason == "max_tokens" {
                text += "\n\n⚠️ Response was truncated (max tokens reached)"
            }
            let usage = decoded.usage.map { TokenUsage(inputTokens: $0.input_tokens, outputTokens: $0.output_tokens) }
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
        guard let url = URL(string: base.trimmingCharacters(in: ["/"]) + "/v1/messages") else {
            throw TranslationError.invalidURL
        }

        let body = RequestBody(
            model: config.model,
            max_tokens: 4096,
            system: PromptBuilder.systemPrompt(for: operation, targetLanguage: config.targetLanguage, magicPrompt: config.magicPrompt),
            messages: [.init(role: "user", content: PromptBuilder.userContent(text))]
        )

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(config.apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(anthropicAPIVersion, forHTTPHeaderField: "anthropic-version")
        request.httpBody = try JSONEncoder().encode(body)

        let data = try await performRequest(request, session: Self.session)

        do {
            let decoded = try JSONDecoder().decode(ResponseBody.self, from: data)
            var text = decoded.content.compactMap { $0.text }.joined()
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { throw TranslationError.emptyResponse }
            if decoded.stop_reason == "max_tokens" {
                text += "\n\n⚠️ Response was truncated (max tokens reached)"
            }
            let usage = decoded.usage.map { TokenUsage(inputTokens: $0.input_tokens, outputTokens: $0.output_tokens) }
            return ProviderResult(text: text, usage: usage)
        } catch let error as TranslationError {
            throw error
        } catch {
            throw TranslationError.decoding(error.localizedDescription)
        }
    }
}
