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
            // `.id(selected)` recreates the detail view per provider, so unsaved edits are discarded on switch.
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

    @State private var draft = ProviderDraft()
    @State private var savedFlash: Bool = false
    @State private var savedFlashTask: Task<Void, Never>?
    @State private var hasKey: Bool = false

    private var impl: AIProvider? { providerImpls[provider] }
    private var fields: [ProviderField] { impl?.settingsFields ?? [.apiKey, .baseURL, .model] }
    private var errors: [ProviderField: String] { impl.map { draft.validate(for: $0) } ?? [:] }

    var body: some View {
        Form {
            headerSection

            ApiKeySection(
                requiresKey: fields.contains(.apiKey),
                hasKey: hasKey,
                apiKeyInput: $draft.apiKey,
                saveError: store.apiKeySaveError,
                onClear: clearKey
            )

            if fields.contains(.baseURL) {
                EndpointSection(
                    baseURL: $draft.baseURL,
                    defaultBaseURL: impl?.defaultBaseURL ?? "",
                    autoBaseURL: impl?.autoBaseURL ?? false,
                    errorMessage: errors[.baseURL]
                )
            }

            if fields.contains(.model) {
                ModelSection(model: $draft.model, presets: impl?.availableModels ?? [])
            }

            ProviderExtraFields(fields: fields, referer: $draft.referer, region: $draft.region, errors: errors)

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
                        .disabled(!errors.isEmpty)
                }
                .animation(.easeInOut(duration: 0.2), value: savedFlash)
            }
        }
        .formStyle(.grouped)
        .onAppear { reload() }
        .onChange(of: store.secretsRevision) { _ in hasKey = store.hasApiKey(for: provider) }
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
        let ops = impl?.supportedOperations ?? []
        return AIOperation.allCases.filter { ops.contains($0) }.map { $0.displayName }.joined(separator: " · ")
    }

    private func reload() {
        hasKey = store.hasApiKey(for: provider)
        draft = ProviderDraft(from: store.settings(for: provider))
    }

    private func clearKey() {
        store.setApiKey("", for: provider)
        draft.apiKey = ""
        hasKey = store.hasApiKey(for: provider)
    }

    private func saveAll() {
        guard errors.isEmpty else { return }
        hasKey = draft.apply(to: store, provider: provider)
        draft.apiKey = ""
        savedFlash = true
        savedFlashTask?.cancel()
        savedFlashTask = Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            await MainActor.run { savedFlash = false }
        }
    }
}
