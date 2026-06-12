import Foundation

struct GoogleFreeProvider: AIProvider {

    let type: ProviderType = .googleFree
    let defaultBaseURL = "https://translate.googleapis.com"
    let availableModels: [String] = []
    let requiresApiKey: Bool = false
    let supportedOperations: Set<AIOperation> = [.translate, .screenTranslate]

    private static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        return URLSession(configuration: config)
    }()

    func execute(text: String, operation: AIOperation, config: ProviderConfig) async throws -> ProviderResult {
        guard operation == .translate || operation == .screenTranslate else {
            throw TranslationError.operationNotSupported(provider: type, operation: operation)
        }
        let base = config.baseURL.isEmpty ? defaultBaseURL : config.baseURL
        guard let schemeURL = URL(string: base), schemeURL.scheme == "https" else {
            throw TranslationError.invalidConfiguration("baseURL must use HTTPS scheme")
        }
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

        let data = try await performRequest(request, session: Self.session)

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
