import Foundation

/// Shared HTTP plumbing for all providers: one URLSession, endpoint building, JSON helpers, status handling.
enum ProviderHTTP {

    /// Refuses redirects that change scheme, host or port (prevents leaking API keys to another origin).
    private final class RedirectGuard: NSObject, URLSessionTaskDelegate {
        func urlSession(
            _ session: URLSession,
            task: URLSessionTask,
            willPerformHTTPRedirection response: HTTPURLResponse,
            newRequest request: URLRequest,
            completionHandler: @escaping (URLRequest?) -> Void
        ) {
            let original = task.originalRequest?.url
            let target = request.url
            if let original, let target,
               original.scheme?.lowercased() == target.scheme?.lowercased(),
               original.host?.lowercased() == target.host?.lowercased(),
               original.port == target.port {
                completionHandler(request)
            } else {
                completionHandler(nil)
            }
        }
    }

    private static let redirectGuard = RedirectGuard()

    static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        return URLSession(configuration: config, delegate: redirectGuard, delegateQueue: nil)
    }()

    /// Builds `https://host/<path>` from the user-configured base URL (or the default one).
    static func endpoint(
        baseURL: String,
        defaultBaseURL: String,
        path: String,
        query: [URLQueryItem] = []
    ) throws -> URL {
        let trimmed = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = trimmed.isEmpty ? defaultBaseURL : trimmed
        guard let baseComponents = URLComponents(string: base),
              baseComponents.scheme?.lowercased() == "https" else {
            throw TranslationError.invalidConfiguration("baseURL must use HTTPS scheme")
        }
        guard let host = baseComponents.host, !host.isEmpty else {
            throw TranslationError.invalidURL
        }
        var basePath = baseComponents.path
        while basePath.hasSuffix("/") { basePath.removeLast() }
        let extra = path.hasPrefix("/") ? path : "/" + path

        var components = URLComponents()
        components.scheme = "https"
        components.host = host
        components.port = baseComponents.port
        components.path = basePath + extra
        if !query.isEmpty { components.queryItems = query }
        guard let url = components.url else { throw TranslationError.invalidURL }
        return url
    }

    static func jsonRequest(
        url: URL,
        headers: [String: String] = [:],
        body: some Encodable
    ) throws -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        for (name, value) in headers {
            request.setValue(value, forHTTPHeaderField: name)
        }
        request.httpBody = try JSONEncoder().encode(body)
        return request
    }

    static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw TranslationError.decoding(error.localizedDescription)
        }
    }

    static func perform(_ request: URLRequest) async throws -> Data {
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
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
