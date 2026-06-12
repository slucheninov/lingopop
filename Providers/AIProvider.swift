import Foundation

protocol AIProvider {
    var type: ProviderType { get }
    var defaultBaseURL: String { get }
    var availableModels: [String] { get }
    var requiresApiKey: Bool { get }
    var supportedOperations: Set<AIOperation> { get }
    var supportsVision: Bool { get }
    func execute(text: String, operation: AIOperation, config: ProviderConfig) async throws -> ProviderResult
    func executeVision(image: Data, targetLanguage: String, config: ProviderConfig) async throws -> ProviderResult
}

extension AIProvider {
    var requiresApiKey: Bool { true }
    var supportedOperations: Set<AIOperation> { Set(AIOperation.allCases) }
    var supportsVision: Bool { false }
    func executeVision(image: Data, targetLanguage: String, config: ProviderConfig) async throws -> ProviderResult {
        throw TranslationError.operationNotSupported(provider: type, operation: .screenTranslate)
    }

    func mimeType(for data: Data) -> String {
        guard data.count >= 4 else { return "image/png" }
        let header = data.prefix(4)
        // PNG signature: 89 50 4E 47
        if header.starts(with: [0x89, 0x50, 0x4E, 0x47]) { return "image/png" }
        // JPEG signature: FF D8 FF
        if header.starts(with: [0xFF, 0xD8, 0xFF]) { return "image/jpeg" }
        return "image/png"
    }

    func performRequest(_ request: URLRequest, session: URLSession) async throws -> Data {
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw TranslationError.network(error)
        }
        guard let http = response as? HTTPURLResponse else {
            throw TranslationError.decoding("Not an HTTP response")
        }
        guard (200..<300).contains(http.statusCode) else {
            let urlStr = request.url.map { redactedURL($0.absoluteString) } ?? "<unknown>"
            throw TranslationError.http(status: http.statusCode, body: String(data: data, encoding: .utf8) ?? "", url: urlStr)
        }
        return data
    }
}
