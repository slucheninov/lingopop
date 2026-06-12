import Foundation
import Combine

@MainActor
final class TranslationHistoryStore: ObservableObject {

    private let defaults: UserDefaults
    private let defaultsKey = "LingoPop.history.v1"
    private let cloudFileName = "history.json"

    @Published private(set) var entries: [TranslationHistoryEntry] = []

    var iCloudEnabled: Bool = false
    var syncHistoryToiCloud: Bool = false
    private var lastCloudMTime: Date?
    private var pollTimer: Timer?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        loadInitial()
        installCloudPolling()
    }

    private func loadInitial() {
        if iCloudEnabled, syncHistoryToiCloud, CloudStorage.isAvailable,
           let read = CloudStorage.read(cloudFileName),
           let decoded = try? JSONDecoder().decode([TranslationHistoryEntry].self, from: read.data) {
            entries = decoded
            lastCloudMTime = read.modified
            return
        }
        if let data = defaults.data(forKey: defaultsKey),
           let decoded = try? JSONDecoder().decode([TranslationHistoryEntry].self, from: data) {
            entries = decoded
        }
    }

    private func installCloudPolling() {
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.reloadFromCloudIfNewer() }
        }
    }

    func reloadFromCloudIfNewer() {
        guard iCloudEnabled, syncHistoryToiCloud, CloudStorage.isAvailable else { return }
        guard let cloudMTime = CloudStorage.modificationDate(cloudFileName) else { return }
        if let last = lastCloudMTime, cloudMTime <= last { return }
        guard let read = CloudStorage.read(cloudFileName),
              let decoded = try? JSONDecoder().decode([TranslationHistoryEntry].self, from: read.data) else { return }
        entries = decoded
        lastCloudMTime = read.modified
    }

    func add(_ entry: TranslationHistoryEntry, maxCount: Int) {
        guard maxCount > 0 else {
            entries.removeAll()
            persist()
            return
        }
        var updated = entries
        updated.insert(entry, at: 0)
        if updated.count > maxCount {
            updated = Array(updated.prefix(maxCount))
        }
        entries = updated
        persist()
    }

    func trim(to maxCount: Int) {
        if maxCount <= 0 {
            entries.removeAll()
        } else if entries.count > maxCount {
            entries = Array(entries.prefix(maxCount))
        }
        persist()
    }

    func remove(_ entry: TranslationHistoryEntry) {
        entries.removeAll { $0.id == entry.id }
        persist()
    }

    func clear() {
        entries.removeAll()
        persist()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        defaults.set(data, forKey: defaultsKey)
        if iCloudEnabled, syncHistoryToiCloud, CloudStorage.isAvailable {
            if let mtime = CloudStorage.write(cloudFileName, data: data) {
                lastCloudMTime = mtime
            }
        }
    }
}
