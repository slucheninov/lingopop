import Foundation

struct GeminiProvider: AIProvider {

    let type: ProviderType = .gemini
    let defaultBaseURL = "https://generativelanguage.googleapis.com"
    let availableModels = [
        "gemini-2.5-flash-lite",
        "gemini-2.5-flash",
        "gemini-2.5-pro"
    ]

    private struct RequestBody: Encodable {
        let systemInstruction: Instruction
        let contents: [Content]
        struct Instruction: Encodable {
            let parts: [Part]
        }
        struct Content: Encodable {
            let role: String
            let parts: [Part]
        }
        struct Part: Encodable {
            let text: String
        }
    }

    private struct ResponseBody: Decodable {
        let candidates: [Candidate]
        let usageMetadata: UsageMetadata?
        struct Candidate: Decodable {
            let content: Content?
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

    private struct VisionRequestBody: Encodable {
        let contents: [VisionContent]

        struct VisionContent: Encodable {
            let role: String
            let parts: [VisionPart]

            enum VisionPart: Encodable {
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
    }

    func executeVision(image: Data, targetLanguage: String, config: ProviderConfig) async throws -> ProviderResult {
        guard !config.apiKey.isEmpty else { throw TranslationError.missingApiKey }
        let base = config.baseURL.isEmpty ? defaultBaseURL : config.baseURL
        let encodedKey = config.apiKey.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? config.apiKey
        let urlString = "\(base.trimmingCharacters(in: ["/"]))/v1beta/models/\(config.model):generateContent?key=\(encodedKey)"
        guard let url = URL(string: urlString) else { throw TranslationError.invalidURL }

        let base64 = image.base64EncodedString()
        let prompt = "Extract all text from this image and translate it into \(targetLanguage). Output only the translated text. No explanations, no preamble."

        let body = VisionRequestBody(contents: [
            .init(role: "user", parts: [
                .inlineData(mimeType: "image/jpeg", data: base64),
                .text(prompt)
            ])
        ])

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
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
            let text = decoded.candidates
                .compactMap { $0.content?.parts?.compactMap { $0.text }.joined() }
                .joined()
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { throw TranslationError.emptyResponse }
            let usage = decoded.usageMetadata.map {
                TokenUsage(inputTokens: $0.promptTokenCount, outputTokens: $0.candidatesTokenCount ?? 0)
            }
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
        let encodedKey = config.apiKey.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? config.apiKey
        let urlString = "\(base.trimmingCharacters(in: ["/"]))/v1beta/models/\(config.model):generateContent?key=\(encodedKey)"
        guard let url = URL(string: urlString) else {
            throw TranslationError.invalidURL
        }

        let body = RequestBody(
            systemInstruction: .init(parts: [.init(text: PromptBuilder.systemPrompt(for: operation, targetLanguage: config.targetLanguage))]),
            contents: [.init(role: "user", parts: [.init(text: PromptBuilder.userContent(text))])]
        )

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
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
            let text = decoded.candidates
                .compactMap { $0.content?.parts?.compactMap { $0.text }.joined() }
                .joined()
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { throw TranslationError.emptyResponse }
            let usage = decoded.usageMetadata.map {
                TokenUsage(inputTokens: $0.promptTokenCount, outputTokens: $0.candidatesTokenCount ?? 0)
            }
            return ProviderResult(text: text, usage: usage)
        } catch let error as TranslationError {
            throw error
        } catch {
            throw TranslationError.decoding(error.localizedDescription)
        }
    }
}
