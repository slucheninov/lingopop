import Foundation

/// Codable wrapper that persists a `[ProviderType: Value]` dictionary as a JSON **object** keyed by
/// `ProviderType.rawValue`, e.g. `{"Claude": {...}, "Google (Free)": {...}}`.
///
/// Why: Swift's synthesized `Codable` for a dictionary whose key is a non-`String`/`Int`
/// `RawRepresentable` encodes it as a flat array `[k1, v1, k2, v2]`, which is brittle and unreadable.
///
/// Decoding is lenient:
/// - the new object form and the legacy flat-array form (written by v0.3.17 and older) are both read;
/// - entries whose key is not a known `ProviderType` (e.g. written by a newer app version) are skipped;
/// - entries whose value fails to decode are skipped, so one bad entry never fails the whole blob.
///
/// Encoding always uses the object form. Older versions cannot read it (see AGENTS.md, "Persistence layout").
struct ProviderKeyedDictionary<Value: Codable>: Codable {
    var values: [ProviderType: Value]

    init(_ values: [ProviderType: Value] = [:]) {
        self.values = values
    }

    private struct DynamicKey: CodingKey {
        let stringValue: String
        var intValue: Int? { nil }
        init(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }

    /// Never throws: decodes `T` if possible, otherwise yields nil. Lets an unkeyed container
    /// advance past an element that is malformed or of an unexpected type.
    private struct Lenient<T: Decodable>: Decodable {
        let value: T?
        init(from decoder: Decoder) throws {
            value = try? T(from: decoder)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: DynamicKey.self)
        for (provider, value) in values {
            try container.encode(value, forKey: DynamicKey(stringValue: provider.rawValue))
        }
    }

    init(from decoder: Decoder) throws {
        var result: [ProviderType: Value] = [:]

        if let container = try? decoder.container(keyedBy: DynamicKey.self) {
            for key in container.allKeys {
                guard let provider = ProviderType(rawValue: key.stringValue),
                      let value = try? container.decode(Lenient<Value>.self, forKey: key).value else { continue }
                result[provider] = value
            }
        } else {
            // Legacy synthesized form: [key1, value1, key2, value2, ...].
            var container = try decoder.unkeyedContainer()
            while !container.isAtEnd {
                let key = try container.decode(Lenient<String>.self).value
                if container.isAtEnd { break }
                let value = try container.decode(Lenient<Value>.self).value
                if let key, let provider = ProviderType(rawValue: key), let value {
                    result[provider] = value
                }
            }
        }
        values = result
    }
}
