import Foundation

enum UsagePricing {
    private static let table: [String: (input: Double, output: Double)] = [
        "claude-haiku-4-5":       (0.80,  4.00),
        "claude-sonnet-4-6":      (3.00,  15.00),
        "claude-opus-4-7":        (15.00, 75.00),
        "gpt-5.4-nano":           (0.15,  0.60),
        "gpt-5.4-mini":           (0.60,  2.40),
        "gpt-5.4":                (2.50,  10.00),
        "gpt-5.5":                (5.00,  20.00),
        "gemini-2.5-flash-lite":  (0.075, 0.30),
        "gemini-2.5-flash":       (0.15,  0.60),
        "gemini-2.5-pro":         (1.25,  5.00),
        // Claude — newly added presets
        "claude-sonnet-5":        (2.00,  10.00),
        "claude-opus-5":          (5.00,  25.00),
        "claude-opus-4-8":        (5.00,  25.00),
        "claude-fable-5":         (10.00, 50.00),
        // OpenAI — newly added presets
        "gpt-5.6-luna":           (1.00,  6.00),
        "gpt-5.6-terra":          (2.50,  15.00),
        "gpt-5.6-sol":            (5.00,  30.00),
        "gpt-5.5-pro":            (30.00, 180.00),
        "gpt-4.1":                (2.00,  8.00),
        "gpt-4.1-mini":           (0.40,  1.60),
        // Gemini — newly added presets
        "gemini-3.6-flash":       (1.50,  7.50),
        "gemini-3.5-flash":       (1.50,  9.00),
        "gemini-3.5-flash-lite":  (0.30,  2.50),
        "gemini-3.1-pro-preview": (2.00,  12.00),
        "gemini-3.1-flash-lite":  (0.25,  1.50),
    ]

    static func estimatedCost(model: String, inputTokens: Int, outputTokens: Int) -> Double? {
        guard let prices = table[model] else { return nil }
        return (Double(inputTokens) * prices.input + Double(outputTokens) * prices.output) / 1_000_000
    }
}
