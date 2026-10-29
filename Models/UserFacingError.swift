import Foundation

/// An error whose text is meant to be shown to the user (popup, alert).
///
/// `userSummary` is the short, actionable sentence; `userDetail` is optional
/// technical context that the UI may hide behind a disclosure. Conforming types
/// get `errorDescription` (and therefore `localizedDescription`) for free.
protocol UserFacingError: LocalizedError {
    var userSummary: String { get }
    var userDetail: String? { get }
}

extension UserFacingError {
    var userDetail: String? { nil }
    var errorDescription: String? { userSummary }
}
