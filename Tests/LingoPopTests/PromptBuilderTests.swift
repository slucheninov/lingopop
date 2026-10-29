import XCTest

final class PromptBuilderTests: XCTestCase {
    func test_userContentEscapesAndWraps() {
        XCTAssertEqual(PromptBuilder.userContent("a<b>&c"), "<text>\na&lt;b&gt;&amp;c\n</text>")
    }

    func test_sanitizeOutputInvertsUserContent() {
        let s = "x < y && y > z"
        XCTAssertEqual(PromptBuilder.sanitizeOutput(PromptBuilder.userContent(s)), s)
    }

    func test_sanitizeOutputStripsCaseInsensitiveTagsAndWhitespace() {
        XCTAssertEqual(PromptBuilder.sanitizeOutput("  <TEXT>hi</text>\n"), "hi")
    }

    func test_magicPromptSubstitutesTargetLanguage() {
        let p = PromptBuilder.systemPrompt(for: .magic, targetLanguage: "Polish", magicPrompt: "Answer in {{targetLanguage}}")
        XCTAssertTrue(p.contains("Answer in Polish"))
        XCTAssertFalse(p.contains("{{targetLanguage}}"))
    }

    func test_emptyMagicPromptFallsBackToDefault() {
        XCTAssertEqual(
            PromptBuilder.systemPrompt(for: .magic, targetLanguage: "Polish", magicPrompt: ""),
            PromptBuilder.systemPrompt(for: .magic, targetLanguage: "Polish", magicPrompt: PromptBuilder.defaultMagicPrompt))
    }

    func test_translateAndScreenTranslateShareThePrompt() {
        XCTAssertEqual(
            PromptBuilder.systemPrompt(for: .translate, targetLanguage: "German", magicPrompt: ""),
            PromptBuilder.systemPrompt(for: .screenTranslate, targetLanguage: "German", magicPrompt: ""))
    }
}
