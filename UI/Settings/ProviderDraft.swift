import Foundation

/// Editable, not-yet-saved state of one provider's settings form.
/// The detail view owns one `@State var draft`; sections edit it through bindings,
/// and `apply(to:provider:)` is the single place that persists it.
struct ProviderDraft: Equatable {

    /// Text typed into the API key field. Never pre-filled with the stored key.
    var apiKey: String = ""
    var baseURL: String = ""
    var model: String = ""
    var referer: String = ""
    var region: String = ""

    init() {}

    init(from settings: SettingsStore.ProviderSettings, apiKey: String = "") {
        self.apiKey = apiKey
        self.baseURL = settings.baseURL
        self.model = settings.model
        self.referer = settings.referer ?? ""
        self.region = settings.region ?? ""
    }

    /// Copy with surrounding whitespace removed from every field.
    func trimmed() -> ProviderDraft {
        var copy = self
        copy.apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.baseURL = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.model = model.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.referer = referer.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.region = region.trimmingCharacters(in: .whitespacesAndNewlines)
        return copy
    }

    /// Error message per field; an empty result means the draft can be saved.
    /// Only fields the provider actually shows are validated.
    func validate(for provider: AIProvider) -> [ProviderField: String] {
        let d = trimmed()
        let fields = provider.settingsFields
        var errors: [ProviderField: String] = [:]

        // Empty means "use the default"; anything else must be HTTPS so keys and
        // text are never sent in clear text by a typo.
        if fields.contains(.baseURL), !d.baseURL.isEmpty, !d.baseURL.lowercased().hasPrefix("https://") {
            errors[.baseURL] = "Base URL must start with https://"
        }
        // Referer / region end up in HTTP header values (audit L-4): no CR/LF or other control characters.
        if fields.contains(.referer), Self.containsControlCharacters(d.referer) {
            errors[.referer] = "Referer must not contain control characters"
        }
        if fields.contains(.region), !d.region.isEmpty, !Self.isValidRegion(d.region) {
            errors[.region] = "Region may only contain letters, digits, '-' and '_'"
        }
        return errors
    }

    /// Persists the draft: stores a non-empty typed key, then writes the other fields.
    /// Returns whether a key is actually stored afterwards (`setApiKey` can fail,
    /// see `SettingsStore.apiKeySaveError`). The caller is responsible for validating first.
    @MainActor
    @discardableResult
    func apply(to store: SettingsStore, provider: ProviderType) -> Bool {
        let d = trimmed()
        if !d.apiKey.isEmpty {
            store.setApiKey(d.apiKey, for: provider)
        }
        let hasKey = store.hasApiKey(for: provider)
        store.updateSettings(
            .init(
                baseURL: d.baseURL,
                model: d.model,
                referer: d.referer.isEmpty ? nil : d.referer,
                region: d.region.isEmpty ? nil : d.region
            ),
            for: provider
        )
        return hasKey
    }

    private static func containsControlCharacters(_ value: String) -> Bool {
        value.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) || CharacterSet.newlines.contains($0) }
    }

    private static func isValidRegion(_ value: String) -> Bool {
        value.unicodeScalars.allSatisfy { scalar in
            (scalar.isASCII && (CharacterSet.alphanumerics.contains(scalar))) || scalar == "-" || scalar == "_"
        }
    }
}
