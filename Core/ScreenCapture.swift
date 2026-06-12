import AppKit
import CoreGraphics

enum ScreenCaptureError: Error {
    case tooSmall
    case captureFailed
}

enum ScreenCapture {

    /// Captures the portion of the screen described by `rect`.
    /// `rect` must be in AppKit screen coordinates (origin bottom-left of main screen).
    static func capture(rect: CGRect) throws -> CGImage {
        guard rect.width >= 10, rect.height >= 10 else {
            throw ScreenCaptureError.tooSmall
        }

        // AppKit coordinates have Y=0 at the bottom of the primary screen.
        // CGWindowListCreateImage uses display coordinates with Y=0 at the top.
        // Use the screen that contains the rect so captures on secondary monitors are flipped correctly.
        let screenHeight: CGFloat
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(rect) }) {
            screenHeight = screen.frame.height
        } else {
            guard let h = NSScreen.screens.first?.frame.height else {
                throw ScreenCaptureError.captureFailed
            }
            screenHeight = h
        }
        let cgRect = CGRect(
            x: rect.origin.x,
            y: screenHeight - rect.maxY,
            width: rect.width,
            height: rect.height
        )

        guard let image = CGWindowListCreateImage(
            cgRect,
            .optionOnScreenOnly,
            kCGNullWindowID,
            [.bestResolution]
        ) else {
            throw ScreenCaptureError.captureFailed
        }
        return image
    }
}
