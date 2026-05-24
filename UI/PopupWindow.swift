import AppKit
import Combine
import SwiftUI

@MainActor
final class PopupWindow {

    private var panel: NSPanel?
    private var clickMonitor: Any?
    private var keyMonitor: Any?
    private var phaseCancellable: AnyCancellable?
    let state = PopupState()

    func show(near point: NSPoint) {
        let panel = self.panel ?? makePanel()
        self.panel = panel
        let isNewlyVisible = !panel.isVisible
        if isNewlyVisible {
            position(panel, near: point)
            panel.alphaValue = 0
        }
        panel.orderFrontRegardless()
        installEventMonitors()
        if isNewlyVisible {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.18
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().alphaValue = 1
            }
        }
    }

    func close() {
        removeEventMonitors()
        guard let panel, panel.isVisible else { return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.15
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        }, completionHandler: {
            panel.orderOut(nil)
            panel.alphaValue = 1
        })
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 100),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false

        let host = NSHostingView(rootView: PopupView(state: state, onClose: { [weak self] in
            self?.close()
        }))
        host.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView()
        container.addSubview(host)
        NSLayoutConstraint.activate([
            host.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            host.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            host.topAnchor.constraint(equalTo: container.topAnchor),
            host.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
        panel.contentView = container

        phaseCancellable = state.$phase
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                DispatchQueue.main.async { self?.resizeToFit() }
            }

        return panel
    }

    private func resizeToFit() {
        guard let panel, panel.isVisible,
              let newSize = panel.contentView?.fittingSize,
              newSize != panel.frame.size else { return }
        var frame = panel.frame
        let dy = newSize.height - frame.size.height
        frame.origin.y -= dy
        frame.size = newSize
        panel.setFrame(frame, display: true, animate: false)
    }

    private func position(_ panel: NSPanel, near point: NSPoint) {
        panel.layoutIfNeeded()
        let size = panel.contentView?.fittingSize ?? NSSize(width: 360, height: 120)
        let screen = NSScreen.screens.first(where: { NSMouseInRect(point, $0.frame, false) }) ?? NSScreen.main
        let bounds = screen?.visibleFrame ?? .zero

        var origin = NSPoint(x: point.x + 12, y: point.y - size.height - 12)
        if origin.x + size.width > bounds.maxX {
            origin.x = bounds.maxX - size.width - 8
        }
        if origin.x < bounds.minX {
            origin.x = bounds.minX + 8
        }
        if origin.y < bounds.minY {
            origin.y = point.y + 12
        }
        if origin.y + size.height > bounds.maxY {
            origin.y = bounds.maxY - size.height - 8
        }
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
    }

    private func installEventMonitors() {
        removeEventMonitors()

        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in self?.close() }
        }

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 {
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
