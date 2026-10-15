import AppKit
import CoreGraphics

enum ScreenCaptureError: LocalizedError {
    case tooSmall
    case captureFailed

    var errorDescription: String? {
        switch self {
        case .tooSmall:
            return "The selected area is too small. Select at least 10x10 pixels."
        case .captureFailed:
            return "Could not capture the screen. Check that Screen Recording permission is granted."
        }
    }
}

enum ScreenCapture {

    /// Captures the portion of the screen described by `rect`.
    /// `rect` must be in AppKit screen coordinates (origin bottom-left of main screen).
    static func capture(rect: CGRect) throws -> CGImage {
        guard rect.width >= 10, rect.height >= 10 else {
            throw ScreenCaptureError.tooSmall
        }

        guard let screen = screen(for: rect) else {
            throw ScreenCaptureError.captureFailed
        }
        let captureRect = rect.intersection(screen.frame)
        guard captureRect.width >= 10, captureRect.height >= 10 else {
            throw ScreenCaptureError.tooSmall
        }

        // AppKit screen frames are Y-up; CoreGraphics display bounds are Y-down.
        // Convert through the selected screen's local coordinates for multi-monitor layouts.
        let displayBounds = displayBounds(for: screen)
        let cgRect = CGRect(
            x: displayBounds.origin.x + (captureRect.minX - screen.frame.minX),
            y: displayBounds.origin.y + (screen.frame.maxY - captureRect.maxY),
            width: captureRect.width,
            height: captureRect.height
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

    private static func screen(for rect: CGRect) -> NSScreen? {
        if let containing = NSScreen.screens.first(where: { $0.frame.contains(rect) }) {
            return containing
        }
        var bestScreen: NSScreen?
        var bestArea: CGFloat = 0
        for screen in NSScreen.screens {
            let intersection = screen.frame.intersection(rect)
            guard !intersection.isNull, intersection.width > 0, intersection.height > 0 else { continue }
            let area = intersection.width * intersection.height
            if area > bestArea {
                bestArea = area
                bestScreen = screen
            }
        }
        return bestScreen
    }

    private static func displayBounds(for screen: NSScreen) -> CGRect {
        guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return screen.frame
        }
        return CGDisplayBounds(CGDirectDisplayID(number.uint32Value))
    }
}
