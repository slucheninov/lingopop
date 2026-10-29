import Foundation

/// An immutable, UUID-identified record that can be merged across Macs (history entries, usage records).
protocol CloudMergeable: Identifiable, Codable where ID == UUID {
    /// Creation time; compared against `MergeableEnvelope.clearedBefore`.
    var mergeTimestamp: Date { get }
}

struct CloudTombstone: Codable, Equatable {
    let id: UUID
    let at: Date
}

/// Versioned cloud file format plus the pure merge function used by `TranslationHistoryStore` and `UsageStore`.
///
/// ```
/// { "version": 2, "items": [...], "deleted": [{"id": "...", "at": ...}], "clearedBefore": ... }
/// ```
///
/// Merge = union of items by id, minus tombstoned ids, minus items not newer than `clearedBefore`,
/// union of tombstones (latest `at` wins) and the later watermark. Tombstones older than 90 days are pruned.
/// Legacy files (a bare `[Item]` array written by v0.3.16 and earlier) decode as an envelope with no tombstones.
struct MergeableEnvelope<Item: CloudMergeable>: Codable {
    var version: Int = 2
    var items: [Item]
    var deleted: [CloudTombstone]
    var clearedBefore: Date?

    static var tombstoneRetention: TimeInterval { 90 * 24 * 60 * 60 }

    init(items: [Item] = [], deleted: [CloudTombstone] = [], clearedBefore: Date? = nil) {
        self.items = items
        self.deleted = deleted
        self.clearedBefore = clearedBefore
    }

    /// Decodes the envelope or, failing that, a legacy bare array. `isLegacy` is true for the latter.
    static func decode(_ data: Data) -> (envelope: MergeableEnvelope<Item>, isLegacy: Bool)? {
        let decoder = JSONDecoder()
        if let envelope = try? decoder.decode(MergeableEnvelope<Item>.self, from: data) {
            return (envelope, false)
        }
        if let items = try? decoder.decode([Item].self, from: data) {
            return (MergeableEnvelope<Item>(items: items), true)
        }
        return nil
    }

    func encoded() -> Data? {
        try? JSONEncoder().encode(self)
    }

    var hasSyncMetadata: Bool { !deleted.isEmpty || clearedBefore != nil }

    mutating func markDeleted(_ ids: [UUID], at date: Date = Date()) {
        for id in ids {
            deleted.removeAll { $0.id == id }
            deleted.append(CloudTombstone(id: id, at: date))
        }
    }

    mutating func markCleared(at date: Date = Date()) {
        clearedBefore = Swift.max(clearedBefore ?? date, date)
    }

    /// Pure merge; items keep `self` order first, then remote-only items. Callers sort/cap afterwards.
    func merged(with other: MergeableEnvelope<Item>, now: Date = Date()) -> MergeableEnvelope<Item> {
        var watermark = clearedBefore
        if let theirs = other.clearedBefore { watermark = Swift.max(watermark ?? theirs, theirs) }

        var tombstones: [UUID: Date] = [:]
        for t in deleted + other.deleted {
            tombstones[t.id] = Swift.max(tombstones[t.id] ?? t.at, t.at)
        }

        var seen = Set<UUID>()
        var unionItems: [Item] = []
        for item in items + other.items {
            guard seen.insert(item.id).inserted, tombstones[item.id] == nil else { continue }
            if let watermark, item.mergeTimestamp <= watermark { continue }
            unionItems.append(item)
        }

        let horizon = now.addingTimeInterval(-Self.tombstoneRetention)
        let kept = tombstones
            .filter { $0.value >= horizon }
            .map { CloudTombstone(id: $0.key, at: $0.value) }
            .sorted { ($0.at, $0.id.uuidString) < ($1.at, $1.id.uuidString) }

        return MergeableEnvelope<Item>(items: unionItems, deleted: kept, clearedBefore: watermark)
    }

    /// True when `self` holds items, tombstones or a watermark that `remote` does not, i.e. the remote
    /// file must be rewritten for the other Mac to receive them. Comparing this way (rather than
    /// "differs from remote") keeps Macs with different history caps from rewriting each other forever.
    func carriesContent(missingFrom remote: MergeableEnvelope<Item>) -> Bool {
        let remoteIDs = Set(remote.items.map(\.id))
        if items.contains(where: { !remoteIDs.contains($0.id) }) { return true }
        let remoteTombstones = Set(remote.deleted.map(\.id))
        if deleted.contains(where: { !remoteTombstones.contains($0.id) }) { return true }
        if let mine = clearedBefore {
            guard let theirs = remote.clearedBefore else { return true }
            return mine > theirs
        }
        return false
    }
}

/// Local-vs-iCloud bookkeeping shared by the history and usage stores: tombstones/watermark persistence,
/// merge-on-reload and merge-before-write. The stores keep owning their `@Published` items.
@MainActor
final class CloudMergeSync<Item: CloudMergeable> {
    typealias Envelope = MergeableEnvelope<Item>

    private let defaults: UserDefaults
    private let defaultsKey: String
    private let metaKey: String
    private let cloudFileName: String
    /// Tombstones and watermark only (`items` is always empty here).
    private var meta = Envelope()
    private var lastCloudMTime: Date?

    init(defaults: UserDefaults, defaultsKey: String, cloudFileName: String) {
        self.defaults = defaults
        self.defaultsKey = defaultsKey
        self.metaKey = defaultsKey + ".sync"
        self.cloudFileName = cloudFileName
        if let data = defaults.data(forKey: metaKey), let stored = Envelope.decode(data)?.envelope {
            meta = Envelope(deleted: stored.deleted, clearedBefore: stored.clearedBefore)
        }
    }

    /// The local copy stays a bare array under the original key, so older versions can still read it.
    func loadLocalItems() -> [Item] {
        guard let data = defaults.data(forKey: defaultsKey) else { return [] }
        return Envelope.decode(data)?.envelope.items ?? []
    }

    func recordDeleted(_ ids: [UUID]) { meta.markDeleted(ids) }
    func recordCleared() { meta.markCleared() }

    /// Forget the last seen cloud mtime so the next `pull` merges even if the file did not change
    /// (used when sync is switched on or off).
    func forgetCloudState() { lastCloudMTime = nil }

    /// Merges the cloud file into `local` if it changed since we last looked. Returns the new item list, or nil
    /// when there was nothing to do. `normalize` applies caps/sorting/retention to the merged items.
    func pull(local: [Item], normalize: ([Item]) -> [Item]) -> [Item]? {
        guard let cloudMTime = CloudStorage.modificationDate(cloudFileName) else {
            // No cloud file yet (first enable): publish what we have.
            guard !local.isEmpty || meta.hasSyncMetadata else { return nil }
            return save(local: local, cloudActive: true, normalize: normalize)
        }
        if let last = lastCloudMTime, cloudMTime <= last { return nil }
        guard let read = CloudStorage.read(cloudFileName),
              let remote = Envelope.decode(read.data) else { return nil }
        return reconcile(local: local, remote: remote.envelope, remoteMTime: read.modified, normalize: normalize)
    }

    /// Persists locally and, when `cloudActive`, merges with the current cloud file before writing it so that
    /// items from another Mac are never overwritten. Returns the (possibly merged) items.
    func save(local: [Item], cloudActive: Bool, normalize: ([Item]) -> [Item]) -> [Item] {
        guard cloudActive else {
            persistLocal(local)
            return local
        }
        if CloudStorage.modificationDate(cloudFileName) != nil {
            guard let read = CloudStorage.read(cloudFileName),
                  let remote = Envelope.decode(read.data) else {
                // Cloud file exists but cannot be read or decoded right now (e.g. still downloading): keep it intact.
                persistLocal(local)
                return local
            }
            return reconcile(local: local, remote: remote.envelope, remoteMTime: read.modified, normalize: normalize)
        }
        var merged = Envelope(items: local, deleted: meta.deleted, clearedBefore: meta.clearedBefore)
        merged.items = normalize(merged.items)
        writeCloud(merged)
        persistLocal(merged.items)
        return merged.items
    }

    private func reconcile(local: [Item], remote: Envelope,
                           remoteMTime: Date, normalize: ([Item]) -> [Item]) -> [Item] {
        let mine = Envelope(items: local, deleted: meta.deleted, clearedBefore: meta.clearedBefore)
        var merged = mine.merged(with: remote)
        merged.items = normalize(merged.items)
        lastCloudMTime = remoteMTime
        // A legacy bare-array file is upgraded to the envelope on the next write, not eagerly.
        if merged.carriesContent(missingFrom: remote) { writeCloud(merged) }
        meta = Envelope(deleted: merged.deleted, clearedBefore: merged.clearedBefore)
        persistLocal(merged.items)
        return merged.items
    }

    private func writeCloud(_ envelope: Envelope) {
        guard let data = envelope.encoded(), let mtime = CloudStorage.write(cloudFileName, data: data) else { return }
        lastCloudMTime = mtime
    }

    private func persistLocal(_ items: [Item]) {
        if let data = try? JSONEncoder().encode(items) { defaults.set(data, forKey: defaultsKey) }
        if let data = meta.encoded() { defaults.set(data, forKey: metaKey) }
    }
}
