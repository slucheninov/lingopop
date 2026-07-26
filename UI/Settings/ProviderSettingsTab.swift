import SwiftUI

struct ProviderSettingsTab: View {

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
                        Image(systemName: type.sfSymbol)
                            .font(.system(size: 14))
                            .foregroundStyle(type.iconColor)
                            .frame(width: 18)
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
    @State private var savedFlashTask: Task<Void, Never>?
    @State private var hasKey: Bool = false
    @State private var showEndpointHelp: Bool = false

    private var requiresKey: Bool { providerImpls[provider]?.requiresApiKey ?? true }
    private var supportedOps: Set<AIOperation> { providerImpls[provider]?.supportedOperations ?? [] }

    var body: some View {
        Form {
            Section {
                HStack(spacing: 10) {
                    Image(systemName: provider.sfSymbol)
                        .font(.system(size: 24))
                        .foregroundStyle(provider.iconColor)
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
                    if let error = store.apiKeySaveError {
                        Text(error)
                            .foregroundColor(.red)
                            .font(.caption)
                    }
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
                HStack(spacing: 8) {
                    TextField("Base URL", text: $baseURL)
                        .textFieldStyle(.roundedBorder)
                        .autocorrectionDisabled(true)
                    Button {
                        showEndpointHelp = true
                    } label: {
                        Image(systemName: "questionmark.circle")
                    }
                    .buttonStyle(.borderless)
                    .help("Show default endpoint")
                    .popover(isPresented: $showEndpointHelp) {
                        Text("Default: \(providerImpls[provider]?.defaultBaseURL ?? "")")
                            .padding()
                            .frame(maxWidth: 280)
                    }
                    Button {
                        baseURL = providerImpls[provider]?.defaultBaseURL ?? baseURL
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                    }
                    .buttonStyle(.borderless)
                    .help("Reset to default endpoint")
                    .disabled(baseURL == (providerImpls[provider]?.defaultBaseURL ?? baseURL))
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
        .onDisappear { savedFlashTask?.cancel() }
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
        savedFlashTask?.cancel()
        savedFlashTask = Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            await MainActor.run { savedFlash = false }
        }
    }
}
