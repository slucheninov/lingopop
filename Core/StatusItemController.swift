import AppKit

@MainActor
final class StatusItemController {

    enum State {
        case idle
        case translating
        case error
    }

    private(set) var statusItem: NSStatusItem?
    private var spinTimer: Timer?
    private var spinIndex = 0
    private var errorResetTask: Task<Void, Never>?
    private(set) var state: State = .idle

    func install(menu: NSMenu) -> NSStatusItem {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.menu = menu
        statusItem = item
        apply(.idle)
        return item
    }

    func apply(_ state: State) {
        self.state = state
        errorResetTask?.cancel()
        stopSpin()

        switch state {
        case .idle:
            guard let button = statusItem?.button else { break }
            button.image = makeIdleImage()
            button.contentTintColor = nil
        case .translating:
            startSpin()
        case .error:
            setSymbol("exclamationmark.triangle.fill", tint: .systemRed)
            errorResetTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                guard let self, !Task.isCancelled else { return }
                if self.state == .error { self.apply(.idle) }
            }
        }
    }

    private func makeIdleImage() -> NSImage {
        let font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.black]
        let str = NSAttributedString(string: "AЇ", attributes: attrs)
        let sz = str.size()
        let image = NSImage(size: sz, flipped: false) { _ in str.draw(at: .zero); return true }
        image.isTemplate = true
        return image
    }

    private func setSymbol(_ name: String, tint: NSColor?) {
        guard let button = statusItem?.button else { return }
        let image = NSImage(systemSymbolName: name, accessibilityDescription: "LingoPop")
        image?.isTemplate = (tint == nil)
        button.image = image
        button.contentTintColor = tint
    }

    private func startSpin() {
        guard statusItem?.button != nil else { return }
        let frames = ["arrow.triangle.2.circlepath", "arrow.triangle.2.circlepath.circle"]
        spinIndex = 0
        setSymbol(frames[0], tint: nil)
        spinTimer = Timer.scheduledTimer(withTimeInterval: 0.45, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.spinIndex = (self.spinIndex + 1) % frames.count
                self.setSymbol(frames[self.spinIndex], tint: nil)
            }
        }
    }

    private func stopSpin() {
        spinTimer?.invalidate()
        spinTimer = nil
    }
}
