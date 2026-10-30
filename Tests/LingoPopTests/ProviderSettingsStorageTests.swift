import XCTest

final class ProviderSettingsStorageTests: XCTestCase {

    private let claude = ProviderConnectionSettings(baseURL: "https://api.anthropic.com", model: "m1", referer: nil, region: nil)
    private let ms = ProviderConnectionSettings(baseURL: "https://ms", model: "", referer: nil, region: "westeurope")
    private let google = ProviderConnectionSettings(baseURL: "https://g", model: "", referer: "https://ref", region: nil)

    // MARK: SecretsPayload

    func test_decodesOldKeyOnlyFormat() throws {
        let plaintext = Data(#"{"apiKey.Claude":"sk-1","apiKey.Google (Free)":"x"}"#.utf8)
        let entries = try XCTUnwrap(SecretsPayload.decode(plaintext))
        XCTAssertEqual(entries, ["apiKey.Claude": "sk-1", "apiKey.Google (Free)": "x"])
        XCTAssertEqual(SecretsPayload.providerSettings(in: entries), .absent)
    }

    func test_rejectsNonFlatStringMap() {
        XCTAssertNil(SecretsPayload.decode(Data(#"{"version":2,"secrets":{}}"#.utf8)))
        XCTAssertNil(SecretsPayload.decode(Data("[1,2]".utf8)))
    }

    func test_providerSettingsRoundTripKeepsApiKeys() throws {
        var entries = ["apiKey.Claude": "sk-1"]
        try SecretsPayload.setProviderSettings([.claude: claude, .microsoftTranslator: ms, .googleCloud: google], in: &entries)
        let reread = try XCTUnwrap(SecretsPayload.decode(try SecretsPayload.encode(entries)))
        XCTAssertEqual(reread["apiKey.Claude"], "sk-1")
        XCTAssertEqual(SecretsPayload.providerSettings(in: reread),
                       .loaded([.claude: claude, .microsoftTranslator: ms, .googleCloud: google]))
    }

    func test_newPayloadIsStillAFlatStringMapForOlderReaders() throws {
        var entries = ["apiKey.DeepL": "k"]
        try SecretsPayload.setProviderSettings([.deepl: claude], in: &entries)
        let plaintext = try SecretsPayload.encode(entries)
        let flat = try JSONDecoder().decode([String: String].self, from: plaintext)
        XCTAssertEqual(flat["apiKey.DeepL"], "k")
        XCTAssertNotNil(flat[SecretsPayload.providerSettingsEntry])
    }

    func test_setProviderSettingsPreservesUnknownEntries() throws {
        var entries = ["apiKey.Claude": "k", "futureEntry": "v"]
        try SecretsPayload.setProviderSettings([:], in: &entries)
        XCTAssertEqual(entries["futureEntry"], "v")
        XCTAssertEqual(SecretsPayload.providerSettings(in: entries), .loaded([:]))
    }

    func test_providerSettingsSkipsUnknownProviderAndBadEntry() {
        let raw = #"{"version":1,"providers":{"Claude":{"baseURL":"u","model":"m"},"Bogus":{"baseURL":"u","model":"m"},"DeepL":{"baseURL":5}}}"#
        let entries = [SecretsPayload.providerSettingsEntry: raw]
        XCTAssertEqual(SecretsPayload.providerSettings(in: entries),
                       .loaded([.claude: ProviderConnectionSettings(baseURL: "u", model: "m", referer: nil, region: nil)]))
    }

    func test_corruptProviderSettingsEntryIsUnavailable() {
        XCTAssertEqual(SecretsPayload.providerSettings(in: [SecretsPayload.providerSettingsEntry: "not json"]), .unavailable)
    }

    func test_legacyFlatArrayProviderBlobDecodes() throws {
        // The UserDefaults blob written by v0.3.17 and older used a flat [key, value, ...] array.
        let json = #"["Claude",{"baseURL":"u","model":"m"},"DeepL",{"baseURL":"","model":""}]"#
        let decoded = try JSONDecoder().decode(ProviderKeyedDictionary<ProviderConnectionSettings>.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.values.keys.sorted { $0.rawValue < $1.rawValue }, [.claude, .deepl])
    }

    // MARK: ProviderSettingsMigration

    func test_migrate_unavailableKeepsLegacyAndTouchesNothing() {
        let plan = ProviderSettingsMigration.plan(secure: .unavailable, legacy: [.claude: claude])
        XCTAssertEqual(plan, .init(providers: [.claude: claude], writeSecure: false, clearLegacy: false))
    }

    func test_migrate_unavailableWithoutLegacyUsesDefaults() {
        let plan = ProviderSettingsMigration.plan(secure: .unavailable, legacy: nil)
        XCTAssertEqual(plan, .init(providers: nil, writeSecure: false, clearLegacy: false))
    }

    func test_migrate_absentWithLegacyWritesThenClears() {
        let plan = ProviderSettingsMigration.plan(secure: .absent, legacy: [.claude: claude])
        XCTAssertEqual(plan, .init(providers: [.claude: claude], writeSecure: true, clearLegacy: true))
    }

    func test_migrate_absentWithoutLegacyDoesNothing() {
        let plan = ProviderSettingsMigration.plan(secure: .absent, legacy: nil)
        XCTAssertEqual(plan, .init(providers: nil, writeSecure: false, clearLegacy: false))
    }

    func test_migrate_loadedWithoutLegacyIsIdempotent() {
        let plan = ProviderSettingsMigration.plan(secure: .loaded([.claude: claude]), legacy: nil)
        XCTAssertEqual(plan, .init(providers: [.claude: claude], writeSecure: false, clearLegacy: false))
    }

    func test_migrate_loadedEqualToLegacyOnlyClearsLegacy() {
        let plan = ProviderSettingsMigration.plan(secure: .loaded([.claude: claude]), legacy: [.claude: claude])
        XCTAssertEqual(plan, .init(providers: [.claude: claude], writeSecure: false, clearLegacy: true))
    }

    func test_migrate_legacyWinsPerProviderAndFillsGaps() {
        let newer = ProviderConnectionSettings(baseURL: "https://new", model: "m2", referer: nil, region: nil)
        let plan = ProviderSettingsMigration.plan(secure: .loaded([.claude: claude, .microsoftTranslator: ms]),
                                                  legacy: [.claude: newer, .googleCloud: google])
        XCTAssertEqual(plan.providers, [.claude: newer, .microsoftTranslator: ms, .googleCloud: google])
        XCTAssertTrue(plan.writeSecure)
        XCTAssertTrue(plan.clearLegacy)
    }

    func test_migrate_secondRunAfterSuccessIsNoop() {
        let first = ProviderSettingsMigration.plan(secure: .absent, legacy: [.claude: claude])
        let second = ProviderSettingsMigration.plan(secure: .loaded(first.providers ?? [:]), legacy: nil)
        XCTAssertEqual(second, .init(providers: [.claude: claude], writeSecure: false, clearLegacy: false))
    }
}
