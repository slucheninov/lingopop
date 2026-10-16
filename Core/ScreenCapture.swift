import AppKit
import CoreGraphics
import ScreenCaptureKit

enum ScreenCaptureError: UserFacingError {
    case tooSmall
    case captureFailed

    var userSummary: String {
        switch self {
        case .tooSmall:
            return String(localized: "Selection is too small. Try selecting a larger area.")
        case .captureFailed:
            return String(localized: "Could not capture the screen. Check that Screen Recording permission is granted.")
        }
    }
}

enum ScreenCapture {

    /// Captures the portion of the screen described by `rect`.
    /// `rect` must be in AppKit screen coordinates (origin bottom-left of main screen).
    ///
    /// macOS 14+ uses ScreenCaptureKit; macOS 13 falls back to `CGWindowListCreateImage`.
    /// Throws `CancellationError` if the surrounding task was cancelled.
    static func capture(rect: CGRect) async throws -> CGImage {
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

        if #available(macOS 14.0, *) {
            return try await captureWithScreenCaptureKit(captureRect: captureRect, screen: screen)
        }
        return try captureWithCoreGraphics(captureRect: captureRect, screen: screen)
    }

    // MARK: - ScreenCaptureKit (macOS 14+)

    @available(macOS 14.0, *)
    private static func captureWithScreenCaptureKit(captureRect: CGRect, screen: NSScreen) async throws -> CGImage {
        guard let displayID = displayID(for: screen) else {
            throw ScreenCaptureError.captureFailed
        }

        do {
            try Task.checkCancellation()
            // Without Screen Recording permission this throws; mapped to `captureFailed` below.
            let content = try await SCShareableContent.current
            guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
                throw ScreenCaptureError.captureFailed
            }

            // Nothing is excluded: the old CGWindowList path captured everything on screen, and
            // the selection overlay panels are already ordered out by the time we get here.
            let filter = SCContentFilter(display: display, excludingWindows: [])

            // `sourceRect` is in the display's point space with a top-left origin, relative to
            // that display (not global coordinates). AppKit frames are Y-up, so flip within
            // the selected screen.
            let sourceRect = CGRect(
                x: captureRect.minX - screen.frame.minX,
                y: screen.frame.maxY - captureRect.maxY,
                width: captureRect.width,
                height: captureRect.height
            )

            let config = SCStreamConfiguration()
            config.sourceRect = sourceRect
            // Output size is in pixels: scale points by the backing scale for Retina output.
            let scale = screen.backingScaleFactor
            config.width = max(1, Int((captureRect.width * scale).rounded()))
            config.height = max(1, Int((captureRect.height * scale).rounded()))
            config.showsCursor = false

            let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
            try Task.checkCancellation()
            return image
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as ScreenCaptureError {
            throw error
        } catch {
            throw ScreenCaptureError.captureFailed
        }
    }

    // MARK: - CoreGraphics (macOS 13 fallback)

    /// `CGWindowListCreateImage` is deprecated since macOS 14 but is the only built-in region
    /// capture API on macOS 13 (ScreenCaptureKit screenshots need macOS 14). Kept isolated here;
    /// marked deprecated so calling the deprecated API inside does not emit a warning.
    @available(macOS, deprecated: 14.0, message: "macOS 13 fallback; ScreenCaptureKit is used on 14+")
    private static func captureWithCoreGraphics(captureRect: CGRect, screen: NSScreen) throws -> CGImage {
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

    private static func displayID(for screen: NSScreen) -> CGDirectDisplayID? {
        guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return nil
        }
        return CGDirectDisplayID(number.uint32Value)
    }

    private static func displayBounds(for screen: NSScreen) -> CGRect {
        guard let id = displayID(for: screen) else {
            return screen.frame
        }
        return CGDisplayBounds(id)
    }
}
