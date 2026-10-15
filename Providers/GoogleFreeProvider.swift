import Foundation

struct GoogleFreeProvider: AIProvider {

    let type: ProviderType = .googleFree
    let defaultBaseURL = "https://translate.googleapis.com"
    let availableModels: [String] = []
    let requiresApiKey: Bool = false
    let supportedOperations: Set<AIOperation> = [.translate, .screenTranslate]

    func execute(text: String, operation: AIOperation, config: ProviderConfig) async throws -> ProviderResult {
        let url = try ProviderHTTP.endpoint(
            baseURL: config.baseURL,
            defaultBaseURL: defaultBaseURL,
            path: "/translate_a/single",
            query: [
                URLQueryItem(name: "client", value: "gtx"),
                URLQueryItem(name: "sl", value: "auto"),
                URLQueryItem(name: "tl", value: LanguageCodes.code(for: config.targetLanguage)),
                URLQueryItem(name: "dt", value: "t"),
                URLQueryItem(name: "q", value: text)
            ]
        )

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")

        let data = try await ProviderHTTP.perform(request)

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
        return ProviderResult(text: result, usage: nil)
    }
}
