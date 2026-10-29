import AppKit

/// Session state of the last operation. Retry / Rewrite / Explain / Replace re-run
/// from it, and Screen Translate fills it in. Shared by `AppDelegate`,
/// `ScreenTranslateFlow` and the `PopupActions` handlers.
@MainActor
final class OperationSession {
    var lastCapturedText: String?
    var lastCursorPosition: NSPoint?
    var lastDetectedSource: String?
    var lastTargetLanguage: String?
    var lastOperation: AIOperation = .translate
    var lastCapturedImage: NSImage?
    /// The app that was frontmost before the hotkey fired (target of Replace).
    var previousApp: NSRunningApplication?
}
