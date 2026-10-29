import Foundation
import Combine

@MainActor
final class UsageStore: ObservableObject {

    struct Record: Codable, Identifiable {
        let id: UUID
        let timestamp: Date
        let provider: ProviderType
        let model: String
        let operation: AIOperation
        let inputTokens: Int
        let outputTokens: Int
    }

    enum Period { case day, days7, days30 }

    struct ProviderTotals {
        let inputTokens: Int
        let outputTokens: Int
        let calls: Int
        let estimatedCost: Double?
    }

    struct Bucket {
        let start: Date
        var byProvider: [ProviderType: (input: Int, output: Int)]
    }

    private let sync: CloudMergeSync<Record>

    var iCloudEnabled: Bool = false {
        didSet { if oldValue != iCloudEnabled { sync.forgetCloudState() } }
    }
    // Only mutated on the main actor; invalidated in the nonisolated deinit (no other reference exists then).
    nonisolated(unsafe) private var pollTimer: Timer?

    @Published private(set) var records: [Record] = []

    init(defaults: UserDefaults = .standard) {
        sync = CloudMergeSync(defaults: defaults, defaultsKey: "LingoPop.usage.v1", cloudFileName: "usage.json")
        records = sync.loadLocalItems()
        installCloudPolling()
    }

    deinit {
        pollTimer?.invalidate()
    }

    // MARK: - Mutations

    func append(_ record: Record) {
        records.append(record)
        persist()
    }

    func reset() {
        sync.recordCleared()
        records = []
        persist()
    }

    // MARK: - Aggregation

    func records(in period: Period) -> [Record] {
        records.filter { $0.timestamp >= period.cutoffDate }
    }

    func totals(in period: Period) -> (inputTokens: Int, outputTokens: Int, calls: Int, estimatedCost: Double?) {
        let rs = records(in: period)
        let input = rs.reduce(0) { $0 + $1.inputTokens }
        let output = rs.reduce(0) { $0 + $1.outputTokens }
        let costs = rs.compactMap { UsagePricing.estimatedCost(model: $0.model, inputTokens: $0.inputTokens, outputTokens: $0.outputTokens) }
        return (input, output, rs.count, costs.isEmpty ? nil : costs.reduce(0, +))
    }

    func totalsByProvider(in period: Period) -> [ProviderType: ProviderTotals] {
        let rs = records(in: period)
        var grouped: [ProviderType: [Record]] = [:]
        for r in rs { grouped[r.provider, default: []].append(r) }
        return grouped.mapValues { prs in
            let input = prs.reduce(0) { $0 + $1.inputTokens }
            let output = prs.reduce(0) { $0 + $1.outputTokens }
            let costs = prs.compactMap { UsagePricing.estimatedCost(model: $0.model, inputTokens: $0.inputTokens, outputTokens: $0.outputTokens) }
            return ProviderTotals(inputTokens: input, outputTokens: output, calls: prs.count, estimatedCost: costs.isEmpty ? nil : costs.reduce(0, +))
        }
    }

    func chartBuckets(in period: Period) -> [Bucket] {
        let rs = records(in: period)
        let cal = Calendar.current
        let now = Date()
        let today = cal.startOfDay(for: now)

        let allSlots: [Date]
        switch period {
        case .day:
            allSlots = (0..<24).compactMap { cal.date(byAdding: .hour, value: $0, to: today) }
        case .days7:
            allSlots = (0..<7).compactMap { cal.date(byAdding: .day, value: -6 + $0, to: today) }
        case .days30:
            allSlots = (0..<30).compactMap { cal.date(byAdding: .day, value: -29 + $0, to: today) }
        }

        var map: [Date: [ProviderType: (input: Int, output: Int)]] = [:]
        for r in rs {
            let slot: Date
            switch period {
            case .day:
                let comps = cal.dateComponents([.year, .month, .day, .hour], from: r.timestamp)
                slot = cal.date(from: comps) ?? today
            case .days7, .days30:
                slot = cal.startOfDay(for: r.timestamp)
            }
            var byProv = map[slot] ?? [:]
            let existing = byProv[r.provider] ?? (0, 0)
            byProv[r.provider] = (existing.0 + r.inputTokens, existing.1 + r.outputTokens)
            map[slot] = byProv
        }

        return allSlots.map { Bucket(start: $0, byProvider: map[$0] ?? [:]) }
    }

    // MARK: - Persistence

    /// Merges the cloud file into the local records (union by id, tombstones / reset watermark applied) and writes
    /// the result back if this Mac has records the cloud file lacks.
    func reloadFromCloudIfNewer() {
        guard cloudActive else { return }
        guard let merged = sync.pull(local: records, normalize: normalize) else { return }
        publish(merged)
    }

    private var cloudActive: Bool { iCloudEnabled && CloudStorage.isAvailable }

    private func installCloudPolling() {
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.reloadFromCloudIfNewer() }
        }
    }

    /// 31-day retention, oldest first.
    private func normalize(_ items: [Record]) -> [Record] {
        var result = items
        if let cutoff = Calendar.current.date(byAdding: .day, value: -31, to: Calendar.current.startOfDay(for: Date())) {
            result.removeAll { $0.timestamp < cutoff }
        }
        return result.sorted { $0.timestamp < $1.timestamp }
    }

    private func persist() {
        publish(sync.save(local: normalize(records), cloudActive: cloudActive, normalize: normalize))
    }

    private func publish(_ items: [Record]) {
        if items.map(\.id) != records.map(\.id) { records = items }
    }
}

extension UsageStore.Record: CloudMergeable {
    var mergeTimestamp: Date { timestamp }
}

extension UsageStore.Period {
    var cutoffDate: Date {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        switch self {
        case .day:   return today
        // Same calendar-day buckets as UsageStore.chartBuckets: today plus the previous 6 / 29 days.
        case .days7: return cal.date(byAdding: .day, value: -6, to: today) ?? today
        case .days30: return cal.date(byAdding: .day, value: -29, to: today) ?? today
        }
    }
}
