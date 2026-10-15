import SwiftUI

struct ProviderSidebar: View {
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
        // `hasApiKey` reads a UserDefaults flag, which SwiftUI can't observe. Reading
        // `secretsRevision` ties this row to key set/clear so the badge refreshes.
        let _ = store.secretsRevision
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
