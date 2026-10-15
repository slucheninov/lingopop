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

    private var impl: AIProvider? { providerImpls[provider] }
    private var requiresKey: Bool { impl?.requiresApiKey ?? true }
    private var supportedOps: Set<AIOperation> { impl?.supportedOperations ?? [] }

    /// Empty means "use the default"; anything else must be HTTPS so keys and
    /// text are never sent in clear text by a typo.
    private var baseURLError: String? {
        let trimmed = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed.lowercased().hasPrefix("https://") { return nil }
        return "Base URL must start with https://"
    }

    var body: some View {
        Form {
            headerSection

            ApiKeySection(
                requiresKey: requiresKey,
                hasKey: hasKey,
                apiKeyInput: $apiKeyInput,
                saveError: store.apiKeySaveError,
                onClear: clearKey
            )

            EndpointSection(
                baseURL: $baseURL,
                defaultBaseURL: impl?.defaultBaseURL ?? "",
                autoBaseURL: impl?.autoBaseURL ?? false,
                errorMessage: baseURLError
            )

            ModelSection(model: $model, presets: impl?.availableModels ?? [])

            ProviderExtraFields(provider: provider, referer: $referer, region: $region)

            FallbackSection(store: store, provider: provider)

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
                        .disabled(baseURLError != nil)
                }
                .animation(.easeInOut(duration: 0.2), value: savedFlash)
            }
        }
        .formStyle(.grouped)
        .onAppear { reload() }
        .onDisappear { savedFlashTask?.cancel() }
    }

    private var headerSection: some View {
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
        hasKey = store.hasApiKey(for: provider)
    }

    private func saveAll() {
        guard baseURLError == nil else { return }
        let trimmedKey = apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedKey.isEmpty {
            store.setApiKey(trimmedKey, for: provider)
            apiKeyInput = ""
        }
        // Reflect what is actually stored: setApiKey can fail (see apiKeySaveError).
        hasKey = store.hasApiKey(for: provider)
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

// MARK: - Sections

private struct ApiKeySection: View {
    let requiresKey: Bool
    let hasKey: Bool
    @Binding var apiKeyInput: String
    let saveError: String?
    let onClear: () -> Void

    var body: some View {
        if requiresKey {
            Section("API key") {
                HStack(spacing: 8) {
                    Image(systemName: hasKey ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(hasKey ? .green : .secondary)
                    Text(hasKey ? "A key is stored" : "No key set")
                        .font(.system(size: 12))
                    Spacer()
                    if hasKey {
                        Button("Clear", action: onClear)
                    }
                }
                SecureField(hasKey ? "Enter a new key to replace" : "Paste your API key", text: $apiKeyInput)
                    .textFieldStyle(.roundedBorder)
                if let saveError {
                    Text(saveError)
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
    }
}

private struct EndpointSection: View {
    @Binding var baseURL: String
    let defaultBaseURL: String
    let autoBaseURL: Bool
    let errorMessage: String?
    @State private var showEndpointHelp = false

    var body: some View {
        Section("Endpoint") {
            HStack(spacing: 8) {
                TextField(autoBaseURL ? "Auto (free/pro chosen by key)" : "Base URL", text: $baseURL)
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
                    Text(autoBaseURL
                         ? "Leave blank to choose automatically: keys ending in :fx use api-free.deepl.com, others use \(defaultBaseURL)."
                         : "Default: \(defaultBaseURL)")
                        .padding()
                        .frame(maxWidth: 280)
                }
                Button {
                    baseURL = autoBaseURL ? "" : defaultBaseURL
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                }
                .buttonStyle(.borderless)
                .help("Reset to default endpoint")
                .disabled(baseURL == (autoBaseURL ? "" : defaultBaseURL))
            }
            if let errorMessage {
                Text(errorMessage)
                    .foregroundColor(.red)
                    .font(.caption)
            }
        }
    }
}

private struct ModelSection: View {
    @Binding var model: String
    let presets: [String]

    var body: some View {
        if !presets.isEmpty {
            Section("Model") {
                HStack {
                    TextField("Model name", text: $model)
                        .textFieldStyle(.roundedBorder)
                        .autocorrectionDisabled(true)
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
}

private struct ProviderExtraFields: View {
    let provider: ProviderType
    @Binding var referer: String
    @Binding var region: String

    var body: some View {
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
    }
}

private struct FallbackSection: View {
    @ObservedObject var store: SettingsStore
    let provider: ProviderType

    var body: some View {
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
    }
}
