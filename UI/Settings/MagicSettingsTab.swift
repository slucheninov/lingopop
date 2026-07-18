import SwiftUI

struct MagicSettingsTab: View {
    @ObservedObject var store: SettingsStore
    @State private var showResetAlert = false
    @State private var draftPrompt: String = ""

    private var charCount: Int {
        draftPrompt.unicodeScalars.count
    }

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Magic runs a single AI call with your custom system prompt. Use {{targetLanguage}} to insert your configured target language automatically.")
                        .foregroundStyle(.secondary)
                        .font(.callout)

                    TextEditor(text: $draftPrompt)
                        .font(.body.monospaced())
                        .frame(minHeight: 120)
                        .onChange(of: draftPrompt) { newVal in
                            if newVal.unicodeScalars.count > 2000 {
                                draftPrompt = String(newVal.unicodeScalars.prefix(2000))
                            }
                        }

                    HStack {
                        Text("\(charCount) / 2000")
                            .font(.caption)
                            .foregroundStyle(charCount >= 1900 ? Color.red : Color.secondary)
                        Spacer()
                        Button("Reset to default") {
                            showResetAlert = true
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.blue)
                        Button("Save") {
                            store.magicPrompt = SettingsStore.sanitizeMagicPrompt(draftPrompt)
                            draftPrompt = store.magicPrompt
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(draftPrompt == store.magicPrompt)
                    }
                }
            } header: {
                Text("System prompt")
            }
        }
        .formStyle(.grouped)
        .onAppear { draftPrompt = store.magicPrompt }
        .alert("Reset prompt?", isPresented: $showResetAlert) {
            Button("Reset", role: .destructive) {
                store.magicPrompt = PromptBuilder.defaultMagicPrompt
                draftPrompt = PromptBuilder.defaultMagicPrompt
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will replace your prompt with the default. Continue?")
        }
    }
}
