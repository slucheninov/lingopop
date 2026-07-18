import AppKit
import SwiftUI

struct AboutTab: View {
    @StateObject private var updater = UpdateChecker.shared

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
            HStack(spacing: 6) {
                Text("Version \(appVersion)").font(.caption).foregroundStyle(.secondary)
                if updater.isChecking {
                    ProgressView().scaleEffect(0.6).frame(width: 14, height: 14)
                }
            }
            Button("Check for updates") {
                Task { await updater.checkNow() }
            }
            .buttonStyle(.plain)
            .font(.system(size: 11))
            .foregroundStyle(.secondary)

            if updater.isUpdateAvailable(currentVersion: appVersion) {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.down.circle.fill")
                        .foregroundStyle(.white)
                    Text("Version \(updater.latestVersion!) available")
                        .fontWeight(.medium)
                        .foregroundStyle(.white)
                    Spacer()
                    Button("Download") {
                        updater.openReleasePage()
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(.white.opacity(0.25))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .foregroundStyle(.white)
                    .fontWeight(.medium)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color.accentColor)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .padding(.horizontal, 32)
            }

            Divider().padding(.vertical, 6)
            Text("Select text anywhere on your Mac, press a shortcut, and get an instant AI translation, grammar fix, or rewrite in a popup near your cursor.")
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Text("Supports Claude, OpenAI, Gemini, and Google Translate. API keys are stored locally in an encrypted file. Settings sync between Macs via iCloud Drive.")
                .font(.system(size: 12))
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 32)
            if let privacyURL = URL(string: "https://github.com/slucheninov/lingopop/blob/main/PRIVACY.md") {
                Link("Privacy Policy", destination: privacyURL)
                    .font(.system(size: 12))
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}
