import SwiftUI

struct HotkeySettingsTab: View {

    @ObservedObject var store: SettingsStore

    var body: some View {
        Form {
            Section("Shortcuts") {
                ForEach(AIOperation.allCases, id: \.self) { op in
                    LabeledContent {
                        OperationHotkeyRow(store: store, operation: op)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: op.systemImage)
                                .foregroundStyle(.secondary)
                            Text(op.displayName)
                        }
                    }
                }
            }
            Section {
                Text("Click a shortcut field, then press a key combination. Use any of ⌃ ⌥ ⇧ ⌘ plus a key. Esc cancels recording. ✕ removes the shortcut.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

private struct OperationHotkeyRow: View {
    @ObservedObject var store: SettingsStore
    let operation: AIOperation

    var body: some View {
        HStack(spacing: 8) {
            HotkeyRecorderField(config: Binding(
                get: { store.hotkey(for: operation) ?? .empty },
                // The recorder only emits real key combos (keyCode 0 is "A", a valid key),
                // so never treat a recorded config as "empty". Clearing uses the ✕ button.
                set: { newValue in
                    store.setHotkey(newValue, for: operation)
                }
            ))
            if store.hotkey(for: operation) != nil {
                Button(action: { store.setHotkey(nil, for: operation) }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
    }
}
