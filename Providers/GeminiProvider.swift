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
        struct Candidate: Decodable {
            let content: Content?
            struct Content: Decodable {
                let parts: [Part]?
                struct Part: Decodable {
                    let text: String?
                }
            }
        }
    }

    func execute(text: String, operation: AIOperation, config: ProviderConfig) async throws -> String {
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
            guard !text.isEmpty else { throw TranslationError.emptyResponse }
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch let error as TranslationError {
            throw error
        } catch {
            throw TranslationError.decoding(error.localizedDescription)
        }
    }
}
