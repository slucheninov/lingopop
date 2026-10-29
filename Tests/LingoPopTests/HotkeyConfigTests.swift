import XCTest

final class HotkeyConfigTests: XCTestCase {
    func test_defaultDisplayString() {
        XCTAssertEqual(HotkeyConfig.default.displayString, "⌥T")
    }

    func test_emptyConfig() {
        XCTAssertTrue(HotkeyConfig.empty.isEmpty)
        XCTAssertEqual(HotkeyConfig.empty.displayString, "Not set")
    }
}
