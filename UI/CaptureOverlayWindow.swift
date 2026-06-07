import AppKit

enum CaptureOverlayError: Error {
    case cancelled
}

final class CaptureOverlayWindow: NSPanel {

    private let ownScreen: NSScreen
    fileprivate let drawingView: OverlayDrawingView

    init(screen: NSScreen) {
        self.ownScreen = screen
        self.drawingView = OverlayDrawingView()
        super.init(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        ignoresMouseEvents = false
        acceptsMouseMovedEvents = true
        hasShadow = false

        drawingView.frame = contentView?.bounds ?? CGRect(origin: .zero, size: ownScreen.frame.size)
        drawingView.autoresizingMask = [.width, .height]
        contentView?.addSubview(drawingView)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    // MARK: - Multi-screen coordinator

    /// Creates one overlay per screen, tracks mouse via a local event monitor so events
    /// are always captured regardless of monitor configuration or backing scale differences.
    /// Returns the selection in global AppKit screen coordinates.
    static func runSelection() async throws -> CGRect {
        let windows = NSScreen.screens.map { CaptureOverlayWindow(screen: $0) }

        return try await withCheckedThrowingContinuation { continuation in
            var startPoint: NSPoint?
            var selectionRect: CGRect?
            var monitor: Any?
            var finished = false

            func finish(_ result: Result<CGRect, Error>) {
                guard !finished else { return }
                finished = true
                if let m = monitor { NSEvent.removeMonitor(m); monitor = nil }
                for w in windows { w.orderOut(nil) }
                NSCursor.arrow.set()
                continuation.resume(with: result)
            }

            func updateDrawing() {
                for w in windows {
                    w.drawingView.selectionScreenRect = selectionRect
                    w.drawingView.screenOrigin = w.ownScreen.frame.origin
                    w.drawingView.setNeedsDisplay(w.drawingView.bounds)
                }
            }

            monitor = NSEvent.addLocalMonitorForEvents(
                matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp, .keyDown]
            ) { event in
                switch event.type {
                case .leftMouseDown:
                    startPoint = NSEvent.mouseLocation
                    selectionRect = nil
                    updateDrawing()

                case .leftMouseDragged:
                    guard let start = startPoint else { return event }
                    let cur = NSEvent.mouseLocation
                    selectionRect = CGRect(
                        x: min(start.x, cur.x),
                        y: min(start.y, cur.y),
                        width: abs(cur.x - start.x),
                        height: abs(cur.y - start.y)
                    )
                    updateDrawing()

                case .leftMouseUp:
                    if let rect = selectionRect, rect.width >= 10, rect.height >= 10 {
                        finish(.success(rect))
                    } else {
                        finish(.failure(CaptureOverlayError.cancelled))
                    }
                    return nil

                case .keyDown where event.keyCode == 53:
                    finish(.failure(CaptureOverlayError.cancelled))
                    return nil

                default: break
                }
                return event
            }

            NSApp.activate(ignoringOtherApps: true)
            NSCursor.crosshair.set()
            for w in windows {
                w.makeKeyAndOrderFront(nil)
            }
        }
    }
}

// MARK: - Drawing-only view

private final class OverlayDrawingView: NSView {

    var selectionScreenRect: CGRect?
    var screenOrigin: NSPoint = .zero

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.3).setFill()
        bounds.fill()

        guard let screenRect = selectionScreenRect,
              screenRect.width > 1, screenRect.height > 1 else { return }

        // Convert global screen coords → this view's local coords.
        let viewRect = CGRect(
            x: screenRect.origin.x - screenOrigin.x,
            y: screenRect.origin.y - screenOrigin.y,
            width: screenRect.width,
            height: screenRect.height
        )

        let clipped = viewRect.intersection(bounds)
        guard !clipped.isNull, !clipped.isEmpty else { return }

        NSColor.clear.setFill()
        clipped.fill(using: .copy)

        NSColor.white.setStroke()
        let border = NSBezierPath(rect: clipped)
        border.lineWidth = 1.5
        border.stroke()

        let label = "\(Int(screenRect.width)) × \(Int(screenRect.height))"
        let attrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: NSColor.white,
            .font: NSFont.systemFont(ofSize: 11, weight: .medium),
            .shadow: {
                let s = NSShadow()
                s.shadowColor = NSColor.black.withAlphaComponent(0.6)
                s.shadowOffset = NSSize(width: 0, height: -1)
                s.shadowBlurRadius = 2
                return s
            }()
        ]
        let labelSize = (label as NSString).size(withAttributes: attrs)
        let labelX = max(clipped.minX + 4, clipped.maxX - labelSize.width - 4)
        let labelY = max(4, clipped.minY - labelSize.height - 4)
        (label as NSString).draw(at: NSPoint(x: labelX, y: labelY), withAttributes: attrs)
    }
}
