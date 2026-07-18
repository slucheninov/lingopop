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
            MagicSettingsTab(store: store)
                .tabItem { Label("Magic", systemImage: "sparkles") }
            AboutTab()
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 720, height: 560)
    }
}
