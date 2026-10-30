import XCTest

final class AppLanguageTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suite: String!
    private let key = AppLanguage.appleLanguagesKey

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
    private func override() -> [String]? {
        AppLanguage.appDomainLanguages(in: defaults, domain: suite)
    }

    private func save(_ language: AppLanguage) {
        language.save(in: defaults, domain: suite)
    }

    private func applyStored() {
        AppLanguage.applyStored(in: defaults, domain: suite)
    }

    // MARK: - Stored choice

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
        XCTAssertEqual(Set(AppLanguage.supportedCodes), Set(AppLanguage.allCases.compactMap(\.localeCode)))
    }

    // MARK: - Override ownership

    func test_saveWritesChoiceAndAppleLanguages() {
        save(.uk)
        XCTAssertEqual(AppLanguage.stored(in: defaults), .uk)
        XCTAssertEqual(override(), ["uk"])
    }

    func test_systemWithForeignValueIsNoOp() {
        defaults.set(["de"], forKey: key)
        save(.system)
        applyStored()
        XCTAssertEqual(AppLanguage.stored(in: defaults), .system)
        XCTAssertEqual(override(), ["de"])
        XCTAssertNil(defaults.object(forKey: AppLanguage.backupKey))
    }

    func test_overrideThenSystemRestoresForeignValue() {
        defaults.set(["de", "en"], forKey: key)
        save(.uk)
        XCTAssertEqual(override(), ["uk"])
        save(.system)
        XCTAssertEqual(override(), ["de", "en"])
        XCTAssertNil(defaults.object(forKey: AppLanguage.backupKey))
    }

    func test_overrideThenSystemWithoutPriorValueRemovesKey() {
        save(.pl)
        XCTAssertEqual(override(), ["pl"])
        save(.system)
        XCTAssertNil(override())
        XCTAssertNil(defaults.object(forKey: AppLanguage.backupKey))
    }

    func test_switchingBetweenExplicitLanguagesKeepsOriginalBackup() {
        defaults.set(["de"], forKey: key)
        save(.uk)
        save(.pl)
        XCTAssertEqual(override(), ["pl"])
        save(.system)
        XCTAssertEqual(override(), ["de"])
    }

    func test_repeatedApplyAtLaunchIsIdempotent() {
        defaults.set(["de"], forKey: key)
        save(.uk)
        applyStored()
        applyStored()
        XCTAssertEqual(override(), ["uk"])
        save(.system)
        applyStored()
        applyStored()
        XCTAssertEqual(override(), ["de"])
    }

    func test_repeatedApplyAtLaunchIdempotentWithoutPriorValue() {
        save(.uk)
        applyStored()
        applyStored()
        XCTAssertEqual(override(), ["uk"])
        save(.system)
        applyStored()
        XCTAssertNil(override())
    }

    func test_applyStoredRestoresOverride() {
        defaults.set("pl", forKey: AppLanguage.defaultsKey)
        applyStored()
        XCTAssertEqual(override(), ["pl"])
    }

    // MARK: - Effective language and Relaunch comparison

    func test_resolve() {
        XCTAssertEqual(AppLanguage.resolve(preferences: ["uk-UA", "en"]), .uk)
        XCTAssertEqual(AppLanguage.resolve(preferences: ["de-DE"]), .de)
        XCTAssertEqual(AppLanguage.resolve(preferences: ["ru", "pl"]), .pl)
        XCTAssertEqual(AppLanguage.resolve(preferences: ["fr", "ja"]), .en)
        XCTAssertEqual(AppLanguage.resolve(preferences: []), .en)
    }

    func test_effective() {
        XCTAssertEqual(AppLanguage.system.effective(systemPreferences: ["pl-PL"]), .pl)
        XCTAssertEqual(AppLanguage.de.effective(systemPreferences: ["pl-PL"]), .de)
    }

    func test_needsRelaunch_noSpuriousButtonAfterNormalLaunch() {
        // System on an English Mac, launched in English.
        XCTAssertFalse(AppLanguage.needsRelaunch(choice: .system, launchedEffective: .en, systemPreferences: ["en-US"]))
        // System on a Ukrainian Mac whose UI resolved to Ukrainian.
        XCTAssertFalse(AppLanguage.needsRelaunch(choice: .system, launchedEffective: .uk, systemPreferences: ["uk-UA", "en"]))
        // Explicit choice that matches the running UI.
        XCTAssertFalse(AppLanguage.needsRelaunch(choice: .de, launchedEffective: .de, systemPreferences: ["en-US"]))
        // Unsupported system language falls back to English, same as at launch.
        XCTAssertFalse(AppLanguage.needsRelaunch(choice: .system, launchedEffective: .en, systemPreferences: ["fr-FR"]))
    }

    func test_needsRelaunch_whenEffectiveLanguageDiffers() {
        XCTAssertTrue(AppLanguage.needsRelaunch(choice: .uk, launchedEffective: .en, systemPreferences: ["en-US"]))
        XCTAssertTrue(AppLanguage.needsRelaunch(choice: .en, launchedEffective: .uk, systemPreferences: ["en-US"]))
    }

    func test_needsRelaunch_launchArgumentCase() {
        // Launched with -AppleLanguages '(uk)' while the stored choice is System on an English Mac:
        // returning the picker to System must still offer a relaunch.
        XCTAssertTrue(AppLanguage.needsRelaunch(choice: .system, launchedEffective: .uk, systemPreferences: ["en-US"]))
        // Picking Ukrainian explicitly matches the running UI.
        XCTAssertFalse(AppLanguage.needsRelaunch(choice: .uk, launchedEffective: .uk, systemPreferences: ["en-US"]))
    }

    func test_systemPreferencesPrefersBackedUpForeignValue() {
        defaults.set(["pl"], forKey: key)
        save(.uk)
        XCTAssertEqual(AppLanguage.systemPreferences(in: defaults, domain: suite), ["pl"])
    }

    func test_systemPreferencesUsesLiveAppDomainValueWhenNotOwned() {
        defaults.set(["de"], forKey: key)
        XCTAssertEqual(AppLanguage.systemPreferences(in: defaults, domain: suite), ["de"])
    }
}
