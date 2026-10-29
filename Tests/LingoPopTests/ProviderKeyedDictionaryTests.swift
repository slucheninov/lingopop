import XCTest

final class ProviderKeyedDictionaryTests: XCTestCase {
    private func decode(_ json: String) throws -> [ProviderType: Int] {
        try JSONDecoder().decode(ProviderKeyedDictionary<Int>.self, from: Data(json.utf8)).values
    }

    func test_encodesObjectKeyedByRawValue() throws {
        let data = try JSONEncoder().encode(ProviderKeyedDictionary<Int>([.claude: 1]))
        XCTAssertEqual(try JSONDecoder().decode([String: Int].self, from: data), ["Claude": 1])
    }

    func test_decodesLegacyFlatArray() throws {
        XCTAssertEqual(try decode(#"["Claude",1,"DeepL",2]"#), [.claude: 1, .deepl: 2])
    }

    func test_skipsUnknownProviderKey() throws {
        XCTAssertEqual(try decode(#"{"Claude":1,"Bogus":2}"#), [.claude: 1])
    }

    func test_skipsUndecodableValue() throws {
        XCTAssertEqual(try decode(#"{"Claude":1,"DeepL":"x"}"#), [.claude: 1])
    }

    func test_topLevelScalarThrows() {
        XCTAssertThrowsError(try decode("42"))
    }

    func test_providerTypeRawValuesAreFrozen() {
        XCTAssertEqual(ProviderType.allCases.map(\.rawValue),
                       ["Claude", "OpenAI", "Gemini", "Grok", "Google (Free)", "Google Translate", "DeepL", "Microsoft Translator"])
    }
}
