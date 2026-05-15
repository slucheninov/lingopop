import Foundation

struct GoogleFreeProvider: AIProvider {

    let type: ProviderType = .googleFree
    let defaultBaseURL = "https://translate.googleapis.com"
    let availableModels: [String] = []
    let requiresApiKey: Bool = false
    let supportedOperations: Set<AIOperation> = [.translate]

    func execute(text: String, operation: AIOperation, config: ProviderConfig) async throws -> String {
        guard operation == .translate else {
            throw TranslationError.operationNotSupported(provider: type, operation: operation)
        }
        let base = config.baseURL.isEmpty ? defaultBaseURL : config.baseURL
        let target = LanguageCodes.code(for: config.targetLanguage)
        var components = URLComponents(string: base.trimmingCharacters(in: ["/"]) + "/translate_a/single")
        components?.queryItems = [
            URLQueryItem(name: "client", value: "gtx"),
            URLQueryItem(name: "sl", value: "auto"),
            URLQueryItem(name: "tl", value: target),
            URLQueryItem(name: "dt", value: "t"),
            URLQueryItem(name: "q", value: text)
        ]
        guard let url = components?.url else {
            throw TranslationError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")

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

        guard let json = try? JSONSerialization.jsonObject(with: data) else {
            throw TranslationError.decoding("Invalid JSON")
        }
        guard let outer = json as? [Any],
              let segments = outer.first as? [Any] else {
            throw TranslationError.decoding("Unexpected response shape")
        }
        let translated = segments.compactMap { segment -> String? in
            guard let arr = segment as? [Any], let piece = arr.first as? String else { return nil }
            return piece
        }.joined()

        let result = translated.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !result.isEmpty else { throw TranslationError.emptyResponse }
        return result
    }
}
