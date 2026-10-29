import Foundation

struct PopupError: Equatable {
    let message: String
    let details: String?

    init(message: String, details: String? = nil) {
        self.message = message
        self.details = details
    }

    /// Single mapping from any `Error` to popup text:
    /// - `UserFacingError` -> its summary / detail
    /// - anything else -> `localizedDescription`
    ///
    /// `CancellationError` must never be presented; callers drop it before mapping
    /// (`PopupState.setError(_:)` ignores it as a safety net).
    static func from(_ error: Error) -> PopupError {
        if let userFacing = error as? UserFacingError {
            return PopupError(message: userFacing.userSummary, details: userFacing.userDetail)
        }
        return PopupError(message: error.localizedDescription)
    }
}
