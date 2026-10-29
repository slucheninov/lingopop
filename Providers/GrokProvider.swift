import Foundation

/// xAI Grok — OpenAI-compatible `/v1/chat/completions` at api.x.ai.
extension OpenAIProvider {
    static let grok = OpenAIProvider(
        type: .grok,
        defaultBaseURL: "https://api.x.ai",
        availableModels: [
            "grok-4.7",
            "grok-4.6",
            "grok-4.5",
            "grok-4.3",
            "grok-4.20-0309-reasoning",
            "grok-4.20-0309-non-reasoning",
            "grok-build-0.1"
        ]
    )
}
