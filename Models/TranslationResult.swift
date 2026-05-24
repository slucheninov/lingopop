import Foundation

struct TranslationResult {
    let original: String
    let translated: String
    let targetLanguage: String
    let provider: ProviderType
    let operation: AIOperation
    var viaFallback: Bool = false
}

enum TranslationError: LocalizedError {
    case missingApiKey
    case invalidURL
    case http(status: Int, body: String, url: String)
    case decoding(String)
    case emptyResponse
    case network(Error)
    case operationNotSupported(provider: ProviderType, operation: AIOperation)

    var userSummary: String {
        switch self {
        case .missingApiKey:
            return "API key is not set. Open Settings → Provider and add one."
        case .invalidURL:
            return "Invalid base URL."
        case .http(let status, _, _):
            return Self.hint(forStatus: status) ?? "Request failed (HTTP \(status))."
        case .decoding:
            return "Failed to parse the provider response."
        case .emptyResponse:
            return "Provider returned empty translation."
        case .network:
            return "Network error. Check your connection and try again."
        case .operationNotSupported(let provider, let operation):
            return "\(provider.rawValue) doesn't support \(operation.displayName.lowercased()). Switch to an LLM provider (Claude / OpenAI / Gemini) in Settings → Provider."
        }
    }

    var technicalDetails: String? {
        switch self {
        case .http(let status, let body, let url):
            let trimmedBody = String(body.prefix(280)).trimmingCharacters(in: .whitespacesAndNewlines)
            var parts = ["HTTP \(status) from \(url)"]
            if !trimmedBody.isEmpty { parts.append(trimmedBody) }
            return parts.joined(separator: "\n")
        case .decoding(let detail):
            return detail
        case .network(let error):
            return error.localizedDescription
        default:
            return nil
        }
    }

    var errorDescription: String? {
        if let details = technicalDetails {
            return "\(userSummary)\n\n\(details)"
        }
        return userSummary
    }

    private static func hint(forStatus status: Int) -> String? {
        switch status {
        case 401, 403: return "Check the API key in Settings → Provider."
        case 404: return "Endpoint not found. Verify Base URL and Model in Settings."
        case 429: return "Rate limit exceeded. Wait a moment and retry."
        case 500...599: return "Server error from your endpoint. If you use a proxy (LiteLLM), check the model name is configured there."
        default: return nil
        }
    }
}
