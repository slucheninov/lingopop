import Foundation
import Combine
import os

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

    private let defaultsKey = "LingoPop.usage.v1"
    private let cloudFileName = "usage.json"
    private let defaults: UserDefaults

    var iCloudEnabled: Bool = false
    private var lastCloudMTime: Date?
    private var pollTimer: Timer?
    private let log = Logger(subsystem: "com.lingopop.app", category: "UsageStore")

    @Published private(set) var records: [Record] = []

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        loadInitial()
        installCloudPolling()
    }

    // MARK: - Mutations

    func append(_ record: Record) {
        records.append(record)
        persist()
    }

    func reset() {
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

    func reloadFromCloudIfNewer() {
        guard iCloudEnabled, CloudStorage.isAvailable else { return }
        guard let cloudMTime = CloudStorage.modificationDate(cloudFileName) else { return }
        if let last = lastCloudMTime, cloudMTime <= last { return }
        guard let read = CloudStorage.read(cloudFileName),
              let decoded = try? JSONDecoder().decode([Record].self, from: read.data) else { return }
        records = decoded
        lastCloudMTime = read.modified
    }

    private func loadInitial() {
        if iCloudEnabled, CloudStorage.isAvailable,
           let read = CloudStorage.read(cloudFileName),
           let decoded = try? JSONDecoder().decode([Record].self, from: read.data) {
            records = decoded
            lastCloudMTime = read.modified
            return
        }
        if let data = defaults.data(forKey: defaultsKey),
           let decoded = try? JSONDecoder().decode([Record].self, from: data) {
            records = decoded
        }
    }

    private func installCloudPolling() {
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.reloadFromCloudIfNewer() }
        }
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(records) else { return }
        defaults.set(data, forKey: defaultsKey)
        if iCloudEnabled, CloudStorage.isAvailable {
            if let mtime = CloudStorage.write(cloudFileName, data: data) {
                lastCloudMTime = mtime
            }
        }
    }
}

extension UsageStore.Period {
    var cutoffDate: Date {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        switch self {
        case .day:   return today
        case .days7: return cal.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        case .days30: return cal.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        }
    }
}
