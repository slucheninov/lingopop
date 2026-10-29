import Foundation
import Combine

@MainActor
final class TranslationHistoryStore: ObservableObject {

    private let cloudFileName = "history.json"
    private let sync: CloudMergeSync<TranslationHistoryEntry>

    @Published private(set) var entries: [TranslationHistoryEntry] = []

    var iCloudEnabled: Bool = false {
        didSet { if oldValue != iCloudEnabled { sync.forgetCloudState() } }
    }
    var syncHistoryToiCloud: Bool = false {
        didSet { if oldValue != syncHistoryToiCloud { sync.forgetCloudState() } }
    }
    /// Last cap passed to `add` / `trim`; applied after every cloud merge. Nil until the first call.
    private var maxCount: Int?
    private var pollTimer: Timer?

    private var cloudActive: Bool { iCloudEnabled && syncHistoryToiCloud && CloudStorage.isAvailable }

    init(defaults: UserDefaults = .standard) {
        sync = CloudMergeSync(defaults: defaults, defaultsKey: "LingoPop.history.v1", cloudFileName: cloudFileName)
        entries = sync.loadLocalItems()
        installCloudPolling()
    }

    deinit {
        pollTimer?.invalidate()
    }

    private func installCloudPolling() {
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.reloadFromCloudIfNewer() }
        }
    }

    /// Merges the cloud file into the local entries (union by id, tombstones applied) and writes the result back
    /// if this Mac has entries or deletions the cloud file lacks.
    func reloadFromCloudIfNewer() {
        guard cloudActive else { return }
        guard let merged = sync.pull(local: entries, normalize: normalize) else { return }
        publish(merged)
    }

    func add(_ entry: TranslationHistoryEntry, maxCount: Int) {
        self.maxCount = maxCount
        guard maxCount > 0 else {
            entries.removeAll()
            persist()
            return
        }
        entries.insert(entry, at: 0)
        persist()
    }

    func trim(to maxCount: Int) {
        self.maxCount = maxCount
        persist()
    }

    func remove(_ entry: TranslationHistoryEntry) {
        sync.recordDeleted([entry.id])
        entries.removeAll { $0.id == entry.id }
        persist()
    }

    func clear() {
        sync.recordCleared()
        entries.removeAll()
        persist()
    }

    /// Newest first, capped at `maxCount`. Entries dropped by the cap are not tombstoned: they are only
    /// forgotten locally.
    private func normalize(_ items: [TranslationHistoryEntry]) -> [TranslationHistoryEntry] {
        let sorted = items.sorted { $0.timestamp > $1.timestamp }
        guard let maxCount else { return sorted }
        return Array(sorted.prefix(max(maxCount, 0)))
    }

    private func persist() {
        publish(sync.save(local: normalize(entries), cloudActive: cloudActive, normalize: normalize))
    }

    private func publish(_ items: [TranslationHistoryEntry]) {
        if items.map(\.id) != entries.map(\.id) { entries = items }
    }
}
