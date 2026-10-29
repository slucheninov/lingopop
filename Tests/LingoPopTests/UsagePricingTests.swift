import XCTest

final class UsagePricingTests: XCTestCase {
    func test_knownModelCost() throws {
        let cost = try XCTUnwrap(UsagePricing.estimatedCost(model: "claude-sonnet-4-6", inputTokens: 1_000_000, outputTokens: 1_000_000))
        XCTAssertEqual(cost, 18.0, accuracy: 1e-9)
    }

    func test_unknownModelIsNil() {
        XCTAssertNil(UsagePricing.estimatedCost(model: "no-such-model", inputTokens: 1, outputTokens: 1))
    }

    func test_geminiFlashInputOnly() throws {
        let cost = try XCTUnwrap(UsagePricing.estimatedCost(model: "gemini-2.5-flash", inputTokens: 1_000_000, outputTokens: 0))
        XCTAssertEqual(cost, 0.15, accuracy: 1e-9)
    }
}
