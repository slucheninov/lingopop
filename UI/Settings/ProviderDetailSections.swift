import SwiftUI

// Sections of the provider detail form. Each takes bindings into the `ProviderDraft`
// (or plain values) so none of them touches the store except `FallbackSection`.

struct ApiKeySection: View {
    let requiresKey: Bool
    let hasKey: Bool
    @Binding var apiKeyInput: String
    let saveError: String?
    let guideURL: URL
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
                guideLink("How to get an API key")
            }
        } else {
            Section("API key") {
                HStack(spacing: 8) {
                    Label("No key needed", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                        .font(.system(size: 12))
                    Spacer()
                    guideLink("About this provider (no key needed)")
                }
            }
        }
    }

    /// Opens the setup guide in the default browser (`Link` uses NSWorkspace under the hood).
    private func guideLink(_ title: String) -> some View {
        Link(destination: guideURL) {
            Label(title, systemImage: "arrow.up.right.square")
                .font(.caption)
        }
        .foregroundStyle(Color.accentColor)
        .help("Opens the setup guide in your browser")
    }
}

struct EndpointSection: View {
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

struct ModelSection: View {
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

/// Provider-specific optional fields (`referer`, `region`), driven by `AIProvider.settingsFields`.
struct ProviderExtraFields: View {
    let fields: [ProviderField]
    @Binding var referer: String
    @Binding var region: String
    let errors: [ProviderField: String]

    var body: some View {
        if fields.contains(.referer) {
            Section("HTTP Referer (optional)") {
                TextField("https://your-allowed-referer/", text: $referer)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled(true)
                Text("Use this if your API key has 'HTTP referrers' restriction set in Google Cloud Console.")
                    .font(.caption).foregroundStyle(.secondary)
                errorText(for: .referer)
            }
        }

        if fields.contains(.region) {
            Section("Region (optional)") {
                TextField("e.g. eastus", text: $region)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled(true)
                Text("Required for multi-service or regional Azure resources. Leave empty for global free-tier (F0) resources.")
                    .font(.caption).foregroundStyle(.secondary)
                errorText(for: .region)
            }
        }
    }

    @ViewBuilder
    private func errorText(for field: ProviderField) -> some View {
        if let message = errors[field] {
            Text(message)
                .foregroundColor(.red)
                .font(.caption)
        }
    }
}

struct FallbackSection: View {
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
