import AppKit
import Carbon.HIToolbox
import SwiftUI

@MainActor
final class PopupWindow {

    private var panel: NSPanel?
    private var clickMonitor: Any?
    private var keyMonitor: Any?
    private var resizeObserver: NSObjectProtocol?
    private var isClosing: Bool = false
    /// Where the popup was requested and the visible area of that screen, kept so the
    /// panel can be re-placed when its content (and thus size) changes.
    private var anchor: NSPoint = .zero
    private var anchorVisibleFrame: NSRect = .zero
    /// Top-left corner of the frame we last set; AppKit's resize keeps it fixed, so a
    /// different value means the user dragged the panel.
    private var lastTopLeft: NSPoint = .zero
    let state: PopupState
    /// Weak: the actions object (AppDelegate) owns this window.
    private weak var actions: PopupActions?

    /// The only place where the popup is wired to its actions; a window without
    /// actions cannot be created.
    init(actions: PopupActions) {
        self.actions = actions
        self.state = PopupState(actions: actions)
    }

    func show(near point: NSPoint) {
        isClosing = false
        let panel = self.panel ?? makePanel()
        self.panel = panel
        let isNewlyVisible = !panel.isVisible
        if isNewlyVisible {
            position(panel, near: point)
            panel.alphaValue = 0
        } else {
            // Re-shown while a close fade is in flight (or already visible):
            // cancel the animation and make sure the panel is fully opaque.
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0
                panel.animator().alphaValue = 1
            }
            panel.alphaValue = 1
        }
        panel.orderFrontRegardless()
        installEventMonitors()
        if isNewlyVisible {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = PopupLayout.fadeInDuration
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().alphaValue = 1
            }
        }
    }

    func close() {
        removeEventMonitors()
        actions?.popupDidClose()
        guard let panel, panel.isVisible else { return }
        isClosing = true
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = PopupLayout.fadeOutDuration
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            DispatchQueue.main.async {
                guard self?.isClosing == true else { return }
                panel.orderOut(nil)
                panel.alphaValue = 1
                self?.isClosing = false
            }
        })
    }

    deinit {
        if let resizeObserver { NotificationCenter.default.removeObserver(resizeObserver) }
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: PopupLayout.panelWidth, height: PopupLayout.minPanelHeight),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false

        // The hosting controller publishes SwiftUI's ideal size as its
        // `preferredContentSize`, and AppKit resizes the panel to follow it, keeping
        // the top-left corner fixed (so the popup grows downward). This replaces the
        // old Combine + `fittingSize` polling, and also reacts to size changes that do
        // not change `phase` (font size, disclosure groups) and while a Menu is tracking.
        let hosting = NSHostingController(rootView: PopupView(state: state, onClose: { [weak self] in
            self?.close()
        }))
        hosting.sizingOptions = [.preferredContentSize]
        panel.contentViewController = hosting
        // The shadow of a transparent borderless panel is cached; refresh it on resize.
        resizeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResizeNotification, object: panel, queue: .main
        ) { [weak self, weak panel] _ in
            guard let self, let panel else { return }
            MainActor.assumeIsolated {
                panel.invalidateShadow()
                self.keepOnScreen(panel)
            }
        }

        return panel
    }

    private func position(_ panel: NSPanel, near point: NSPoint) {
        panel.layoutIfNeeded()
        // With only `.preferredContentSize` in sizingOptions the hosting view may report a
        // zero fittingSize before its first layout pass, so fall back step by step.
        var size = panel.contentView?.fittingSize ?? .zero
        if size.width <= 0 || size.height <= 0 {
            size = panel.contentViewController?.preferredContentSize ?? .zero
        }
        if size.width <= 0 || size.height <= 0 {
            size = NSSize(width: PopupLayout.panelWidth, height: PopupLayout.fallbackPanelHeight)
        }
        let screen = NSScreen.screens.first(where: { NSMouseInRect(point, $0.frame, false) })
            ?? NSScreen.main
            ?? NSScreen.screens.first
        anchor = point
        anchorVisibleFrame = screen?.visibleFrame ?? CGRect(x: 0, y: 0, width: 800, height: 600)

        let frame = placement(for: size)
        lastTopLeft = NSPoint(x: frame.minX, y: frame.maxY)
        panel.setFrame(frame, display: true)
    }

    private func placement(for size: NSSize) -> NSRect {
        PopupPlacement.frame(
            size: size, anchor: anchor, visibleFrame: anchorVisibleFrame,
            offset: PopupLayout.cursorOffset, inset: PopupLayout.screenEdgeInset
        )
    }

    /// Re-places the panel after a resize so growing content never runs under the Dock
    /// or off-screen. If the user dragged the panel it is only clamped into the screen.
    private func keepOnScreen(_ panel: NSPanel) {
        guard panel.isVisible, !anchorVisibleFrame.isEmpty else { return }
        let current = panel.frame
        let wasDragged = abs(current.minX - lastTopLeft.x) > 0.5 || abs(current.maxY - lastTopLeft.y) > 0.5
        let target: NSRect
        if wasDragged {
            let bounds = anchorVisibleFrame.insetBy(dx: PopupLayout.screenEdgeInset, dy: PopupLayout.screenEdgeInset)
            target = PopupPlacement.clamp(current, into: bounds)
        } else {
            target = placement(for: current.size)
        }
        guard abs(target.minX - current.minX) > 0.5 || abs(target.minY - current.minY) > 0.5 else { return }
        lastTopLeft = NSPoint(x: target.minX, y: target.maxY)
        panel.setFrameOrigin(target.origin)
    }

    private func installEventMonitors() {
        removeEventMonitors()

        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in self?.close() }
        }

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == UInt16(kVK_Escape) {
                self?.close()
                return nil
            }
            return event
        }
    }

    private func removeEventMonitors() {
        if let m = clickMonitor { NSEvent.removeMonitor(m); clickMonitor = nil }
        if let m = keyMonitor { NSEvent.removeMonitor(m); keyMonitor = nil }
    }
}
