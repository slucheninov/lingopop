import SwiftUI

/// Tabs of the Settings window; `SettingsNavigation.tab` selects the visible one.
enum SettingsTab: Hashable {
    case main, providers, shortcuts, usage, magic, about
}

/// Lets the owner of the Settings window switch tabs (e.g. the menu-bar "About" item).
@MainActor
final class SettingsNavigation: ObservableObject {
    @Published var tab: SettingsTab = .main
}

struct SettingsView: View {

    @ObservedObject var navigation: SettingsNavigation
    @ObservedObject var store: SettingsStore
    @ObservedObject var usageStore: UsageStore
    let providerImpls: [ProviderType: AIProvider]

    var body: some View {
        TabView(selection: $navigation.tab) {
            MainSettingsTab(store: store)
                .tabItem { Label("Main", systemImage: "slider.horizontal.3") }
                .tag(SettingsTab.main)
            ProviderSettingsTab(store: store, providerImpls: providerImpls)
                .tabItem { Label("Providers", systemImage: "cpu") }
                .tag(SettingsTab.providers)
            HotkeySettingsTab(store: store)
                .tabItem { Label("Shortcuts", systemImage: "command") }
                .tag(SettingsTab.shortcuts)
            UsageSettingsTab(store: usageStore)
                .tabItem { Label("Usage", systemImage: "chart.bar.xaxis") }
                .tag(SettingsTab.usage)
            MagicSettingsTab(store: store)
                .tabItem { Label("Magic", systemImage: "sparkles") }
                .tag(SettingsTab.magic)
            AboutTab()
                .tabItem { Label("About", systemImage: "info.circle") }
                .tag(SettingsTab.about)
        }
        .frame(width: 720, height: 560)
    }
}
