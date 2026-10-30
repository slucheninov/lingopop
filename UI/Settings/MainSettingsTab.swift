import SwiftUI

struct MainSettingsTab: View {

    @ObservedObject var store: SettingsStore
    @State private var accessibilityGranted: Bool = PermissionsManager.isAccessibilityGranted()
    @State private var screenRecordingGranted: Bool = PermissionsManager.isScreenRecordingGranted()
    @AppStorage(PopupPrefs.fontSizeKey) private var popupFontSize: Double = PopupPrefs.defaultFontSize

    @State private var selectedAppLanguage = AppLanguage.stored()

    /// True when the language the saved choice would produce differs from the one the
    /// running UI was loaded with (also covers a `-AppleLanguages` launch argument).
    private var appLanguageChanged: Bool {
        AppLanguage.needsRelaunch(
            choice: selectedAppLanguage,
            launchedEffective: AppLanguage.launchedEffective,
            systemPreferences: AppLanguage.systemPreferences()
        )
    }

    private var appLanguageBinding: Binding<AppLanguage> {
        Binding(
            get: { selectedAppLanguage },
            set: { newValue in
                selectedAppLanguage = newValue
                newValue.save()
            }
        )
    }

    var body: some View {
        Form {
            Section("Target language") {
                Toggle("Auto-detect input language", isOn: $store.useAutoDetect)
                Picker(store.useAutoDetect ? String(localized: "Default target") : String(localized: "Target"), selection: $store.targetLanguage) {
                    ForEach(Languages.quickList, id: \.self) { lang in
                        Text(lang).tag(lang)
                    }
                    if !Languages.quickList.contains(store.targetLanguage) {
                        Text(store.targetLanguage).tag(store.targetLanguage)
                    }
                }
                if store.useAutoDetect {
                    LanguagePairsEditor(pairs: $store.languagePairs)
                }
            }

            Section("Popup") {
                LabeledContent("Result font size") {
                    HStack(spacing: 8) {
                        Image(systemName: "textformat.size.smaller")
                            .foregroundStyle(.secondary)
                        Slider(value: $popupFontSize, in: 11...20, step: 1)
                            .frame(width: 160)
                        Image(systemName: "textformat.size.larger")
                            .foregroundStyle(.secondary)
                        Text("\(Int(popupFontSize)) pt")
                            .font(.system(size: 12).monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 36, alignment: .trailing)
                    }
                }
            }

            Section("Language") {
                Picker("Language", selection: appLanguageBinding) {
                    ForEach(AppLanguage.allCases) { lang in
                        if let name = lang.nativeName {
                            Text(verbatim: name).tag(lang)
                        } else {
                            Text("System").tag(lang)
                        }
                    }
                }
                if appLanguageChanged {
                    HStack(spacing: 8) {
                        Text("Restart LingoPop to apply the new language.")
                            .font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button("Relaunch") { AppRelauncher.relaunch() }
                    }
                }
            }

            Section("Limits") {
                LabeledContent("Max input characters") {
                    TextField("", value: $store.maxInputChars, format: .number)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 80)
                        .textFieldStyle(.roundedBorder)
                }
                LabeledContent("History size") {
                    Stepper(value: $store.maxHistoryCount, in: 0...100) {
                        Text("\(store.maxHistoryCount)")
                    }
                }
                LabeledContent("Display") {
                    Stepper(value: $store.menuHistoryCount, in: 0...100) {
                        Text("\(store.menuHistoryCount)")
                    }
                }
            }

            Section("Startup") {
                Toggle("Launch at login", isOn: $store.launchAtLogin)
                Toggle("Auto-copy OCR/translation results to clipboard", isOn: $store.autoCopyOCR)
            }

            Section("iCloud Drive sync") {
                HStack(spacing: 8) {
                    Image(systemName: CloudStorage.isAvailable ? "icloud.fill" : "icloud.slash")
                        .foregroundStyle(CloudStorage.isAvailable ? .blue : .secondary)
                    Text(CloudStorage.isAvailable ? String(localized: "iCloud Drive available") : String(localized: "iCloud Drive unavailable"))
                        .font(.system(size: 12))
                    Spacer()
                }
                Toggle("Sync usage statistics via iCloud Drive", isOn: $store.iCloudSync)
                    .disabled(!CloudStorage.isAvailable)
                Toggle("Sync translation history to iCloud", isOn: $store.syncHistoryToiCloud)
                    .disabled(!store.iCloudSync)
                Text("History contains your translated texts. Disabled by default for privacy.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Syncs usage statistics and, if enabled, translation history between Macs signed into the same Apple ID. Settings, provider settings and API keys stay local on each Mac.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            if !accessibilityGranted {
                Section("Accessibility access required") {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.circle.fill")
                            .foregroundStyle(.orange)
                        Text("LingoPop can't read selected text yet.")
                            .font(.system(size: 12))
                        Spacer()
                        Button("Request") { PermissionsManager.requestAccessibility(); refreshAccessibility() }
                        Button("Open Settings") { PermissionsManager.openAccessibilitySettings() }
                    }
                    Text("After granting access, fully quit and relaunch LingoPop.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            } else {
                Section("Accessibility") {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.seal.fill").foregroundStyle(.green)
                        Text("Granted").font(.system(size: 12))
                        Spacer()
                        Button("Re-check") { refreshAccessibility() }
                    }
                }
            }

            if !screenRecordingGranted {
                Section("Screen Recording access required") {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.circle.fill")
                            .foregroundStyle(.orange)
                        Text("Required for Screen Translate.")
                            .font(.system(size: 12))
                        Spacer()
                        Button("Request") { PermissionsManager.requestScreenCaptureAccess(); refreshScreenRecording() }
                        Button("Open Settings") { PermissionsManager.openScreenRecordingSettings() }
                    }
                }
            } else {
                Section("Screen Recording") {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.seal.fill").foregroundStyle(.green)
                        Text("Granted").font(.system(size: 12))
                        Spacer()
                        Button("Re-check") { refreshScreenRecording() }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            refreshAccessibility()
            refreshScreenRecording()
        }
    }

    private func refreshAccessibility() {
        accessibilityGranted = PermissionsManager.isAccessibilityGranted()
    }

    private func refreshScreenRecording() {
        screenRecordingGranted = PermissionsManager.isScreenRecordingGranted()
    }
}

private struct LanguagePairsEditor: View {
    @Binding var pairs: [String: String]
    @State private var newFrom: String = "Russian"
    @State private var newTo: String = "Ukrainian"

    private var orderedKeys: [String] { pairs.keys.sorted() }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Language pairs").font(.system(size: 12, weight: .medium))
            ForEach(orderedKeys, id: \.self) { from in
                HStack(spacing: 8) {
                    Text(from).frame(width: 110, alignment: .leading)
                    Image(systemName: "arrow.right").foregroundStyle(.secondary)
                    Text(pairs[from] ?? "").frame(maxWidth: .infinity, alignment: .leading)
                    Button(action: { pairs.removeValue(forKey: from) }) {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.borderless)
                }
                .font(.system(size: 12))
            }
            Divider()
            HStack(spacing: 8) {
                Picker("", selection: $newFrom) {
                    ForEach(Languages.quickList, id: \.self) { Text($0).tag($0) }
                }
                .labelsHidden().frame(width: 140)
                Image(systemName: "arrow.right").foregroundStyle(.secondary)
                Picker("", selection: $newTo) {
                    ForEach(Languages.quickList, id: \.self) { Text($0).tag($0) }
                }
                .labelsHidden().frame(width: 140)
                Button(action: { pairs[newFrom] = newTo }) {
                    Image(systemName: "plus.circle")
                }
                .buttonStyle(.borderless)
            }
            .font(.system(size: 12))
            Text("If detected source has no pair, the default target is used.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(.top, 2)
    }
}
