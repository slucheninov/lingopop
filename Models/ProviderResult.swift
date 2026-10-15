import Foundation

struct TokenUsage {
    let inputTokens: Int
    let outputTokens: Int
}

struct ProviderResult {
    let text: String
    let usage: TokenUsage?
    var truncated: Bool = false
}
