import XCTest

final class AppLanguageTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suite: String!

    override func setUp() {
        super.setUp()
        suite = "LingoPopTests.AppLanguage.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        defaults = nil
        super.tearDown()
    }

    /// `object(forKey:)` falls back to the global domain, so look at the suite's own domain.
    private func overrideInAppDomain() -> Any? {
        defaults.persistentDomain(forName: suite)?[AppLanguage.appleLanguagesKey]
    }

    func test_defaultIsSystem() {
        XCTAssertEqual(AppLanguage.stored(in: defaults), .system)
    }

    func test_unknownStoredValueFallsBackToSystem() {
        defaults.set("xx", forKey: AppLanguage.defaultsKey)
        XCTAssertEqual(AppLanguage.stored(in: defaults), .system)
    }

    func test_localeCodesAndNames() {
        XCTAssertNil(AppLanguage.system.localeCode)
        XCTAssertNil(AppLanguage.system.nativeName)
        let rows: [(AppLanguage, String, String)] = [
            (.en, "en", "English"), (.pl, "pl", "Polski"),
            (.uk, "uk", "Українська"), (.de, "de", "Deutsch"),
        ]
        for (lang, code, name) in rows {
            XCTAssertEqual(lang.localeCode, code)
            XCTAssertEqual(lang.nativeName, name)
        }
        XCTAssertEqual(AppLanguage.allCases.count, 5)
    }

    func test_saveWritesChoiceAndAppleLanguages() {
        AppLanguage.uk.save(in: defaults)
        XCTAssertEqual(AppLanguage.stored(in: defaults), .uk)
        XCTAssertEqual(defaults.stringArray(forKey: AppLanguage.appleLanguagesKey), ["uk"])
    }

    func test_systemRemovesAppleLanguagesOverride() {
        AppLanguage.de.save(in: defaults)
        AppLanguage.system.save(in: defaults)
        XCTAssertEqual(AppLanguage.stored(in: defaults), .system)
        XCTAssertNil(overrideInAppDomain())
    }

    func test_applyStoredRestoresOverride() {
        defaults.set("pl", forKey: AppLanguage.defaultsKey)
        AppLanguage.applyStored(in: defaults)
        XCTAssertEqual(defaults.stringArray(forKey: AppLanguage.appleLanguagesKey), ["pl"])
    }

    func test_applyStoredWithSystemClearsStaleOverride() {
        defaults.set(["de"], forKey: AppLanguage.appleLanguagesKey)
        AppLanguage.applyStored(in: defaults)
        XCTAssertNil(overrideInAppDomain())
    }
}
