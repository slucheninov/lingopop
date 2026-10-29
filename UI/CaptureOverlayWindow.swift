import AppKit
import Carbon.HIToolbox

enum CaptureOverlayError: UserFacingError {
    case cancelled

    var userSummary: String {
        switch self {
        case .cancelled: return String(localized: "Screen selection was cancelled.")
        }
    }
}

final class CaptureOverlayWindow: NSPanel {

    fileprivate let ownScreen: NSScreen
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
    @MainActor
    static func runSelection() async throws -> CGRect {
        let coordinator = SelectionCoordinator(windows: NSScreen.screens.map { CaptureOverlayWindow(screen: $0) })
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<CGRect, Error>) in
                coordinator.start(with: cont)
            }
        } onCancel: {
            Task { @MainActor in
                coordinator.resumeOnce(.failure(CancellationError()))
            }
        }
    }
}

/// Owns the mutable state of one `runSelection()` call. Main-actor isolated (and therefore
/// `Sendable`), so the event monitor and the cancellation handler can share it safely.
@MainActor
private final class SelectionCoordinator {
    private let windows: [CaptureOverlayWindow]
    private var monitor: Any?
    private var continuation: CheckedContinuation<CGRect, Error>?
    private var finished = false
    private var startPoint: NSPoint?
    private var selectionRect: CGRect?

    init(windows: [CaptureOverlayWindow]) {
        self.windows = windows
    }

    func start(with cont: CheckedContinuation<CGRect, Error>) {
        continuation = cont
        monitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp, .keyDown]
        ) { [self] event in
            // Local monitors are always invoked on the main thread.
            let consumed = MainActor.assumeIsolated { handle(event) }
            return consumed ? nil : event
        }

        NSApp.activate(ignoringOtherApps: true)
        NSCursor.crosshair.set()
        for w in windows {
            w.makeKeyAndOrderFront(nil)
        }

        // A task cancelled before the continuation was stored never ran `onCancel` against it.
        if Task.isCancelled {
            resumeOnce(.failure(CancellationError()))
        }
    }

    /// Returns true when the event was consumed (must not propagate).
    private func handle(_ event: NSEvent) -> Bool {
        switch event.type {
        case .leftMouseDown:
            startPoint = NSEvent.mouseLocation
            selectionRect = nil
            updateDrawing()

        case .leftMouseDragged:
            guard let start = startPoint else { return false }
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
                resumeOnce(.success(rect))
            } else {
                resumeOnce(.failure(CaptureOverlayError.cancelled))
            }
            return true

        case .keyDown where event.keyCode == UInt16(kVK_Escape):
            resumeOnce(.failure(CaptureOverlayError.cancelled))
            return true

        default: break
        }
        return false
    }

    private func updateDrawing() {
        for w in windows {
            w.drawingView.selectionScreenRect = selectionRect
            w.drawingView.screenOrigin = w.ownScreen.frame.origin
            w.drawingView.setNeedsDisplay(w.drawingView.bounds)
        }
    }

    private func teardown() {
        if let m = monitor { NSEvent.removeMonitor(m); monitor = nil }
        for w in windows { w.orderOut(nil) }
        NSCursor.arrow.set()
    }

    /// Single place that resumes the continuation; safe to call repeatedly.
    func resumeOnce(_ result: Result<CGRect, Error>) {
        // No stored continuation yet (cancellation raced ahead of setup): the post-setup
        // `Task.isCancelled` check in `start` will call us again once it exists.
        guard !finished, let cont = continuation else { return }
        finished = true
        continuation = nil
        teardown()
        cont.resume(with: result)
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
