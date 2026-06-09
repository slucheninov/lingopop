import SwiftUI

struct SettingsView: View {

    @ObservedObject var store: SettingsStore
    @ObservedObject var usageStore: UsageStore
    let providerImpls: [ProviderType: AIProvider]

    var body: some View {
        TabView {
            MainSettingsTab(store: store)
                .tabItem { Label("Main", systemImage: "slider.horizontal.3") }
            ProviderSettingsTab(store: store, providerImpls: providerImpls)
                .tabItem { Label("Providers", systemImage: "cpu") }
            HotkeySettingsTab(store: store)
                .tabItem { Label("Shortcuts", systemImage: "command") }
            UsageSettingsTab(store: usageStore)
                .tabItem { Label("Usage", systemImage: "chart.bar.xaxis") }
            AboutTab()
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 720, height: 560)
    }
}

// MARK: - Main Tab

private struct MainSettingsTab: View {

    @ObservedObject var store: SettingsStore
    @State private var accessibilityGranted: Bool = PermissionsManager.isAccessibilityGranted()
    @State private var screenRecordingGranted: Bool = PermissionsManager.isScreenRecordingGranted()
    @AppStorage("LingoPop.popupFontSize") private var popupFontSize: Double = 13

    var body: some View {
        Form {
            Section("Target language") {
                Toggle("Auto-detect input language", isOn: $store.useAutoDetect)
                Picker(store.useAutoDetect ? "Default target" : "Target", selection: $store.targetLanguage) {
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
            }

            Section("Startup") {
                Toggle("Launch at login", isOn: $store.launchAtLogin)
            }

            Section("iCloud Drive sync") {
                HStack(spacing: 8) {
                    Image(systemName: CloudStorage.isAvailable ? "icloud.fill" : "icloud.slash")
                        .foregroundStyle(CloudStorage.isAvailable ? .blue : .secondary)
                    Text(CloudStorage.isAvailable ? "iCloud Drive available" : "iCloud Drive unavailable")
                        .font(.system(size: 12))
                    Spacer()
                }
                Toggle("Sync settings & history via iCloud Drive", isOn: $store.iCloudSync)
                    .disabled(!CloudStorage.isAvailable)
                Text("Syncs settings and translation history between Macs signed into the same Apple ID. API keys stay local per machine.")
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

// MARK: - Providers Tab (sidebar layout)

private struct ProviderSettingsTab: View {

    @ObservedObject var store: SettingsStore
    let providerImpls: [ProviderType: AIProvider]
    @State private var selected: ProviderType = .claude

    var body: some View {
        HStack(spacing: 0) {
            ProviderSidebar(store: store, selected: $selected, providerImpls: providerImpls)
                .frame(width: 220)
            Divider()
            ProviderDetailView(store: store, providerImpls: providerImpls, provider: selected)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .id(selected)
        }
        .onAppear { selected = store.activeProvider }
    }
}

private struct ProviderSidebar: View {
    @ObservedObject var store: SettingsStore
    @Binding var selected: ProviderType
    let providerImpls: [ProviderType: AIProvider]

    var body: some View {
        VStack(spacing: 0) {
            List(selection: $selected) {
                ForEach(ProviderType.allCases, id: \.self) { type in
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 5) {
                                Text(type.rawValue)
                                    .font(.system(size: 13, weight: .medium))
                                if type == store.activeProvider {
                                    Image(systemName: "star.fill")
                                        .font(.system(size: 9))
                                        .foregroundStyle(.yellow)
                                }
                            }
                            providerStatusLine(type)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 2)
                    .tag(type)
                }
            }
            .listStyle(.sidebar)
        }
        .frame(maxHeight: .infinity)
    }

    @ViewBuilder
    private func providerStatusLine(_ type: ProviderType) -> some View {
        let needsKey = providerImpls[type]?.requiresApiKey ?? true
        let hasKey = store.hasApiKey(for: type)
        HStack(spacing: 4) {
            if !needsKey {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(.green)
                Text("No key needed")
            } else if hasKey {
                Image(systemName: "key.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(.green)
                Text("Key set")
            } else {
                Image(systemName: "key")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                Text("No key")
            }
            if let fallback = store.fallback(for: type) {
                Text("· ↳ \(fallback.rawValue)")
            }
        }
        .font(.system(size: 10))
        .foregroundStyle(.secondary)
    }
}

private struct ProviderDetailView: View {

    @ObservedObject var store: SettingsStore
    let providerImpls: [ProviderType: AIProvider]
    let provider: ProviderType

    @State private var apiKeyInput: String = ""
    @State private var baseURL: String = ""
    @State private var model: String = ""
    @State private var referer: String = ""
    @State private var region: String = ""
    @State private var savedFlash: Bool = false
    @State private var hasKey: Bool = false

    private var requiresKey: Bool { providerImpls[provider]?.requiresApiKey ?? true }
    private var supportedOps: Set<AIOperation> { providerImpls[provider]?.supportedOperations ?? [] }

    var body: some View {
        Form {
            Section {
                HStack(spacing: 10) {
                    Image(systemName: "cpu")
                        .font(.system(size: 24))
                        .foregroundStyle(.tint)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(provider.rawValue)
                            .font(.system(size: 16, weight: .semibold))
                        Text(supportedOperationsLabel)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if provider == store.activeProvider {
                        Label("Active", systemImage: "star.fill")
                            .labelStyle(.titleAndIcon)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.yellow)
                    } else {
                        Button("Set as active") { store.activeProvider = provider }
                    }
                }
                .padding(.vertical, 4)
            }

            if requiresKey {
                Section("API key") {
                    HStack(spacing: 8) {
                        Image(systemName: hasKey ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(hasKey ? .green : .secondary)
                        Text(hasKey ? "A key is stored" : "No key set")
                            .font(.system(size: 12))
                        Spacer()
                        if hasKey {
                            Button("Clear") { clearKey() }
                        }
                    }
                    SecureField(hasKey ? "Enter a new key to replace" : "Paste your API key", text: $apiKeyInput)
                        .textFieldStyle(.roundedBorder)
                    Text("Stored locally in an encrypted file (AES-GCM, machine-bound).")
                        .font(.caption).foregroundStyle(.secondary)
                }
            } else {
                Section("API key") {
                    Label("No key needed", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                        .font(.system(size: 12))
                }
            }

            Section("Endpoint") {
                TextField("Base URL", text: $baseURL)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled(true)
                if let placeholder = providerImpls[provider]?.defaultBaseURL {
                    Text("Default: \(placeholder)")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            if !(providerImpls[provider]?.availableModels.isEmpty ?? true) {
                Section("Model") {
                    HStack {
                        TextField("Model name", text: $model)
                            .textFieldStyle(.roundedBorder)
                            .autocorrectionDisabled(true)
                        if let presets = providerImpls[provider]?.availableModels, !presets.isEmpty {
                            Menu {
                                ForEach(presets, id: \.self) { preset in
                                    Button(preset) { model = preset }
                                }
                            } label: {
                                Image(systemName: "list.bullet")
                            }
                            .menuStyle(.borderlessButton)
                            .frame(width: 30)
                        }
                    }
                }
            }

            if provider == .googleCloud {
                Section("HTTP Referer (optional)") {
                    TextField("https://your-allowed-referer/", text: $referer)
                        .textFieldStyle(.roundedBorder)
                        .autocorrectionDisabled(true)
                    Text("Use this if your API key has 'HTTP referrers' restriction set in Google Cloud Console.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            if provider == .microsoftTranslator {
                Section("Region (optional)") {
                    TextField("e.g. eastus", text: $region)
                        .textFieldStyle(.roundedBorder)
                        .autocorrectionDisabled(true)
                    Text("Required for multi-service or regional Azure resources. Leave empty for global free-tier (F0) resources.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            Section("Fallback") {
                LabeledContent("If \(provider.rawValue) fails") {
                    Picker("", selection: Binding(
                        get: { store.fallback(for: provider) },
                        set: { store.setFallback($0, for: provider) }
                    )) {
                        Text("Don't fall back").tag(Optional<ProviderType>.none)
                        ForEach(ProviderType.allCases.filter { $0 != provider }, id: \.self) { type in
                            Text(type.rawValue).tag(Optional(type))
                        }
                    }
                    .labelsHidden()
                    .frame(width: 200)
                }
                Text("Triggered on 429 (rate limit), 5xx (server error), and network errors.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                HStack {
                    if savedFlash {
                        Label("Saved", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green).font(.system(size: 12, weight: .medium))
                            .transition(.opacity)
                    }
                    Spacer()
                    Button("Save") { saveAll() }
                        .keyboardShortcut(.defaultAction)
                        .buttonStyle(.borderedProminent)
                }
                .animation(.easeInOut(duration: 0.2), value: savedFlash)
            }
        }
        .formStyle(.grouped)
        .onAppear { reload() }
    }

    private var supportedOperationsLabel: String {
        let names = AIOperation.allCases.filter { supportedOps.contains($0) }.map { $0.displayName }
        return names.joined(separator: " · ")
    }

    private func reload() {
        apiKeyInput = ""
        hasKey = store.hasApiKey(for: provider)
        let s = store.settings(for: provider)
        baseURL = s.baseURL
        model = s.model
        referer = s.referer ?? ""
        region = s.region ?? ""
    }

    private func clearKey() {
        store.setApiKey("", for: provider)
        apiKeyInput = ""
        hasKey = false
    }

    private func saveAll() {
        let trimmedKey = apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedKey.isEmpty {
            store.setApiKey(trimmedKey, for: provider)
            apiKeyInput = ""
            hasKey = true
        }
        let trimmedReferer = referer.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedRegion = region.trimmingCharacters(in: .whitespacesAndNewlines)
        store.updateSettings(
            .init(
                baseURL: baseURL.trimmingCharacters(in: .whitespacesAndNewlines),
                model: model.trimmingCharacters(in: .whitespacesAndNewlines),
                referer: trimmedReferer.isEmpty ? nil : trimmedReferer,
                region: trimmedRegion.isEmpty ? nil : trimmedRegion
            ),
            for: provider
        )
        savedFlash = true
        Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            await MainActor.run { savedFlash = false }
        }
    }
}

// MARK: - Shortcuts Tab

private struct HotkeySettingsTab: View {

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
                set: { newValue in
                    if newValue.isEmpty {
                        store.setHotkey(nil, for: operation)
                    } else {
                        store.setHotkey(newValue, for: operation)
                    }
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

// MARK: - About Tab

private struct AboutTab: View {

    private var appVersion: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "0.0"
    }

    private var iconImage: NSImage {
        if let image = NSImage(named: "AppIcon") {
            return image
        }
        return NSImage(systemSymbolName: "globe", accessibilityDescription: nil) ?? NSImage()
    }

    var body: some View {
        VStack(spacing: 14) {
            Image(nsImage: iconImage)
                .resizable().scaledToFit().frame(width: 120, height: 120)
                .padding(.top, 16)
            Text("LingoPop").font(.system(size: 26, weight: .semibold))
            Text("Version \(appVersion)").font(.caption).foregroundStyle(.secondary)
            Divider().padding(.vertical, 6)
            Text("Select text anywhere on your Mac, press a shortcut, and get an instant AI translation, grammar fix, or rewrite in a popup near your cursor.")
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Text("Supports Claude, OpenAI, Gemini, and Google Translate. API keys are stored locally in an encrypted file. Settings sync between Macs via iCloud Drive.")
                .font(.system(size: 12))
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 32)
            Link("Privacy Policy", destination: URL(string: "https://github.com/slucheninov/lingopop/blob/main/PRIVACY.md")!)
                .font(.system(size: 12))
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}
