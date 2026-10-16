import Foundation

/// Provider API language codes, derived from the `Languages.all` table. Unknown
/// (custom) names fall back to their lowercased form, as before.
enum LanguageCodes {

    static func code(for name: String) -> String {
        Languages.info(for: name)?.code ?? name.lowercased()
    }

    /// DeepL expects uppercase codes and `NB` for Norwegian.
    static func deepLCode(for name: String) -> String {
        Languages.info(for: name)?.deepLCode ?? code(for: name).uppercased()
    }

    /// Microsoft Translator expects `nb` for Norwegian and `zh-Hans` for (simplified) Chinese.
    static func microsoftCode(for name: String) -> String {
        Languages.info(for: name)?.microsoftCode ?? code(for: name)
    }
}
