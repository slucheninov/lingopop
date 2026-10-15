import AppKit
import Combine
import Foundation

@MainActor
final class UpdateChecker: ObservableObject {
    static let shared = UpdateChecker()

    @Published var latestVersion: String? = nil
    @Published var isChecking: Bool = false

    private var timer: Timer?
    private let checkInterval: TimeInterval = 3 * 60 * 60
    private let apiURL = URL(string: "https://api.github.com/repos/slucheninov/lingopop/releases/latest")!
    private let releasePageURL = URL(string: "https://github.com/slucheninov/lingopop/releases/latest")!
    private let udKeyLastCheck = "LingoPop.lastUpdateCheck"
    private let udKeyLatestVersion = "LingoPop.latestKnownVersion"

    private init() {}

    func startPeriodicChecks() {
        checkIfNeeded()
        timer = Timer.scheduledTimer(withTimeInterval: checkInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.checkIfNeeded() }
        }
    }

    func checkIfNeeded() {
        if let lastCheck = UserDefaults.standard.object(forKey: udKeyLastCheck) as? Date,
           Date().timeIntervalSince(lastCheck) < checkInterval {
            latestVersion = UserDefaults.standard.string(forKey: udKeyLatestVersion)
            return
        }
        Task { await performCheck() }
    }

    func checkNow() async {
        await performCheck()
    }

    func isUpdateAvailable(currentVersion: String) -> Bool {
        guard let latest = latestVersion else { return false }
        return isNewer(latest, than: currentVersion)
    }

    func openReleasePage() {
        NSWorkspace.shared.open(releasePageURL)
    }

    private func performCheck() async {
        isChecking = true
        defer { isChecking = false }
        do {
            var request = URLRequest(url: apiURL, timeoutInterval: 10)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return }
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tagName = json["tag_name"] as? String else { return }
            let version = tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName
            latestVersion = version
            UserDefaults.standard.set(version, forKey: udKeyLatestVersion)
            UserDefaults.standard.set(Date(), forKey: udKeyLastCheck)
        } catch {
            // network errors are silently ignored
        }
    }

    private func isNewer(_ latest: String, than current: String) -> Bool {
        let parse: (String) -> (Int, Int, Int) = { v in
            // Drop pre-release / build suffixes ("1.2.3-beta.1" -> "1.2.3").
            let core = v.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? v
            let p = core.split(separator: ".").compactMap { Int($0) }
            return (p.count > 0 ? p[0] : 0, p.count > 1 ? p[1] : 0, p.count > 2 ? p[2] : 0)
        }
        let l = parse(latest), c = parse(current)
        if l.0 != c.0 { return l.0 > c.0 }
        if l.1 != c.1 { return l.1 > c.1 }
        return l.2 > c.2
    }
}
