import Foundation

/// User actions raised by the popup UI. Implemented by `AppDelegate`
/// (see `App/AppDelegate+PopupActions.swift`); `PopupState` holds it weakly so
/// the popup never keeps the app delegate alive.
@MainActor
protocol PopupActions: AnyObject {
    /// Retry the last operation with another provider.
    func retry(with provider: ProviderType)
    /// Paste `text` back into the app that was frontmost before the popup.
    func replace(with text: String)
    /// Re-run the last translation into a different target language.
    func retranslate(to language: String)
    /// Rewrite the given (usually just translated) text.
    func rewrite(_ text: String)
    /// Explain the given text.
    func explain(_ text: String)
    /// Translate OCR text from a Screen Translate capture with a chosen provider.
    func translateOCR(_ text: String, with provider: ProviderType)
    /// The popup was dismissed; drop any captured session data.
    func popupDidClose()
}
