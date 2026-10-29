import SwiftUI
import AppKit
import Carbon.HIToolbox

struct HotkeyRecorderField: View {

    @Binding var config: HotkeyConfig

    var body: some View {
        HotkeyRecorderRepresentable(config: $config)
            .frame(width: 160, height: 24)
    }
}

private struct HotkeyRecorderRepresentable: NSViewRepresentable {

    @Binding var config: HotkeyConfig

    func makeNSView(context: Context) -> RecorderButton {
        let view = RecorderButton(frame: NSRect(x: 0, y: 0, width: 160, height: 24))
        view.config = config
        view.onChange = { newConfig in
            config = newConfig
        }
        return view
    }

    func updateNSView(_ nsView: RecorderButton, context: Context) {
        nsView.config = config
        nsView.refreshTitle()
    }
}

final class RecorderButton: NSButton {

    var config: HotkeyConfig = .default
    var onChange: ((HotkeyConfig) -> Void)?
    private var recording: Bool = false {
        didSet { refreshTitle() }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        bezelStyle = .rounded
        target = self
        action = #selector(toggleRecording)
        refreshTitle()
    }

    required init?(coder: NSCoder) { fatalError() }

    @objc private func toggleRecording() {
        recording.toggle()
        if recording { window?.makeFirstResponder(self) }
    }

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        guard recording else { super.keyDown(with: event); return }
        let mods: NSEvent.ModifierFlags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        guard !mods.isEmpty else {
            if event.keyCode == UInt16(kVK_Escape) {
                recording = false
                return
            }
            return
        }
        config = HotkeyConfig(keyCode: UInt32(event.keyCode), modifierFlags: mods.rawValue)
        onChange?(config)
        recording = false
    }

    override func flagsChanged(with event: NSEvent) {
        guard recording else { super.flagsChanged(with: event); return }
    }

    func refreshTitle() {
        let label = recording ? String(localized: "Press a key combo…") : config.displayString
        title = label
    }
}
