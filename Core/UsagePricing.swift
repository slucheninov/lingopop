import Foundation

enum UsagePricing {
    private static let table: [String: (input: Double, output: Double)] = [
        "claude-haiku-4-5":      (0.80,  4.00),
        "claude-sonnet-4-6":     (3.00,  15.00),
        "claude-opus-4-7":       (15.00, 75.00),
        "gpt-5.4-nano":          (0.15,  0.60),
        "gpt-5.4-mini":          (0.60,  2.40),
        "gpt-5.4":               (2.50,  10.00),
        "gpt-5.5":               (5.00,  20.00),
        "gemini-2.5-flash-lite": (0.075, 0.30),
        "gemini-2.5-flash":      (0.15,  0.60),
        "gemini-2.5-pro":        (1.25,  5.00),
    ]

    static func estimatedCost(model: String, inputTokens: Int, outputTokens: Int) -> Double? {
        guard let prices = table[model] else { return nil }
        return (Double(inputTokens) * prices.input + Double(outputTokens) * prices.output) / 1_000_000
    }
}
