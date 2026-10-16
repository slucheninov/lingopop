import Foundation
import NaturalLanguage

/// One supported language. This table (`Languages.all`) is the single source of truth:
/// the quick-pick list, every provider's API code and the detector mapping are derived
/// from it, so adding a language is a one-line change here.
struct LanguageInfo {
    /// English display name; also the value stored in settings and sent in prompts.
    let name: String
    /// ISO 639-1 code used by Google Free / Google Cloud (and the base for the other APIs).
    let code: String
    /// DeepL code when it differs from `code.uppercased()`.
    let deepLCode: String?
    /// Microsoft Translator code when it differs from `code`.
    let microsoftCode: String?
    /// `NLLanguage` values the on-device detector maps to this language.
    let nlLanguages: [NLLanguage]
    /// Whether the language appears in the quick-pick lists (menu, popup, settings pickers).
    let inQuickList: Bool

    init(
        _ name: String,
        _ code: String,
        deepL: String? = nil,
        microsoft: String? = nil,
        nl: [NLLanguage],
        quick: Bool = false
    ) {
        self.name = name
        self.code = code
        self.deepLCode = deepL
        self.microsoftCode = microsoft
        self.nlLanguages = nl
        self.inQuickList = quick
    }
}

enum Languages {

    /// The language table. The order of the `quick: true` entries is the order shown in the UI.
    static let all: [LanguageInfo] = [
        LanguageInfo("Ukrainian", "uk", nl: [.ukrainian], quick: true),
        LanguageInfo("English", "en", nl: [.english], quick: true),
        LanguageInfo("Russian", "ru", nl: [.russian], quick: true),
        LanguageInfo("German", "de", nl: [.german], quick: true),
        LanguageInfo("Spanish", "es", nl: [.spanish], quick: true),
        LanguageInfo("French", "fr", nl: [.french], quick: true),
        LanguageInfo("Italian", "it", nl: [.italian], quick: true),
        LanguageInfo("Polish", "pl", nl: [.polish], quick: true),
        LanguageInfo("Portuguese", "pt", nl: [.portuguese], quick: true),
        LanguageInfo("Chinese", "zh", microsoft: "zh-Hans", nl: [.simplifiedChinese, .traditionalChinese], quick: true),
        LanguageInfo("Japanese", "ja", nl: [.japanese], quick: true),
        LanguageInfo("Korean", "ko", nl: [.korean], quick: true),
        LanguageInfo("Turkish", "tr", nl: [.turkish], quick: true),
        LanguageInfo("Arabic", "ar", nl: [.arabic], quick: true),
        LanguageInfo("Dutch", "nl", nl: [.dutch]),
        LanguageInfo("Czech", "cs", nl: [.czech]),
        LanguageInfo("Danish", "da", nl: [.danish]),
        LanguageInfo("Finnish", "fi", nl: [.finnish]),
        LanguageInfo("Greek", "el", nl: [.greek]),
        LanguageInfo("Hebrew", "he", nl: [.hebrew]),
        LanguageInfo("Hindi", "hi", nl: [.hindi]),
        LanguageInfo("Hungarian", "hu", nl: [.hungarian]),
        LanguageInfo("Indonesian", "id", nl: [.indonesian]),
        LanguageInfo("Norwegian", "no", deepL: "NB", microsoft: "nb", nl: [.norwegian]),
        LanguageInfo("Romanian", "ro", nl: [.romanian]),
        LanguageInfo("Swedish", "sv", nl: [.swedish]),
        LanguageInfo("Thai", "th", nl: [.thai]),
        LanguageInfo("Vietnamese", "vi", nl: [.vietnamese])
    ]

    /// Names shown in the language pickers (derived from `all`).
    static let quickList: [String] = all.filter(\.inQuickList).map(\.name)

    private static let byName: [String: LanguageInfo] =
        Dictionary(uniqueKeysWithValues: all.map { ($0.name, $0) })

    private static let byNLLanguage: [NLLanguage: LanguageInfo] = {
        var map: [NLLanguage: LanguageInfo] = [:]
        for info in all {
            for language in info.nlLanguages { map[language] = info }
        }
        return map
    }()

    static func info(for name: String) -> LanguageInfo? {
        byName[name]
    }

    /// The display name for a detected `NLLanguage`, or nil if it is not supported.
    static func name(for language: NLLanguage) -> String? {
        byNLLanguage[language]?.name
    }
}
