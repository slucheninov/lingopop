import NaturalLanguage
import XCTest

final class LanguageCodesTests: XCTestCase {
    func test_codeTable() {
        let rows: [(String, String, String, String)] = [
            ("Ukrainian", "uk", "UK", "uk"),
            ("Chinese", "zh", "ZH", "zh-Hans"),
            ("Norwegian", "no", "NB", "nb"),
            ("Klingon", "klingon", "KLINGON", "klingon"),
        ]
        for (name, code, deepL, ms) in rows {
            XCTAssertEqual(LanguageCodes.code(for: name), code, name)
            XCTAssertEqual(LanguageCodes.deepLCode(for: name), deepL, name)
            XCTAssertEqual(LanguageCodes.microsoftCode(for: name), ms, name)
        }
    }

    func test_quickList() {
        XCTAssertEqual(Languages.quickList.count, 14)
        XCTAssertEqual(Languages.quickList.first, "Ukrainian")
    }

    func test_nameForNLLanguage() {
        XCTAssertEqual(Languages.name(for: .traditionalChinese), "Chinese")
    }
}
