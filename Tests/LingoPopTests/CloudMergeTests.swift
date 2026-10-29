import XCTest

private struct T: CloudMergeable {
    let id: UUID
    let mergeTimestamp: Date
}

final class CloudMergeTests: XCTestCase {
    private typealias Env = MergeableEnvelope<T>
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let day: TimeInterval = 24 * 60 * 60

    private func item(at date: Date? = nil) -> T { T(id: UUID(), mergeTimestamp: date ?? now) }

    func test_merged_unionsItemsById() {
        let x = item(), y = item(), z = item()
        let result = Env(items: [x, y]).merged(with: Env(items: [y, z]), now: now)
        XCTAssertEqual(Set(result.items.map(\.id)), [x.id, y.id, z.id])
        XCTAssertEqual(result.items.count, 3)
    }

    func test_merged_dropsTombstonedItems() {
        let x = item()
        let tomb = CloudTombstone(id: x.id, at: now)
        let result = Env(items: [x]).merged(with: Env(deleted: [tomb]), now: now)
        XCTAssertFalse(result.items.contains { $0.id == x.id })
        XCTAssertEqual(result.deleted, [tomb])
    }

    func test_merged_dropsItemsAtOrBeforeWatermark() {
        let old = item(at: now.addingTimeInterval(-20))
        let edge = item(at: now.addingTimeInterval(-10))
        let fresh = item(at: now)
        let mark = now.addingTimeInterval(-10)
        let result = Env(items: [old, edge, fresh]).merged(with: Env(clearedBefore: mark), now: now)
        XCTAssertEqual(result.items.map(\.id), [fresh.id])
        XCTAssertEqual(result.clearedBefore, mark)
    }

    func test_merged_tombstoneLatestAtWins() {
        let id = UUID()
        let a = Env(deleted: [CloudTombstone(id: id, at: now.addingTimeInterval(-5))])
        let b = Env(deleted: [CloudTombstone(id: id, at: now.addingTimeInterval(-1))])
        let result = a.merged(with: b, now: now)
        XCTAssertEqual(result.deleted.count, 1)
        XCTAssertEqual(result.deleted.first?.at, now.addingTimeInterval(-1))
    }

    func test_merged_prunesTombstonesOlderThanRetention() {
        let stale = CloudTombstone(id: UUID(), at: now.addingTimeInterval(-91 * day))
        let recent = CloudTombstone(id: UUID(), at: now.addingTimeInterval(-89 * day))
        let result = Env(deleted: [stale, recent]).merged(with: Env(), now: now)
        XCTAssertEqual(result.deleted, [recent])
    }

    func test_decode_legacyBareArray() throws {
        let data = try JSONEncoder().encode([item(), item()])
        let decoded = try XCTUnwrap(Env.decode(data))
        XCTAssertTrue(decoded.isLegacy)
        XCTAssertEqual(decoded.envelope.items.count, 2)
    }

    func test_decode_envelopeRoundTrip() throws {
        let tomb = CloudTombstone(id: UUID(), at: now)
        let env = Env(items: [item(), item()], deleted: [tomb], clearedBefore: now.addingTimeInterval(-3))
        let decoded = try XCTUnwrap(Env.decode(try XCTUnwrap(env.encoded())))
        XCTAssertFalse(decoded.isLegacy)
        XCTAssertEqual(decoded.envelope.items.map(\.id), env.items.map(\.id))
        XCTAssertEqual(decoded.envelope.deleted, [tomb])
        XCTAssertEqual(decoded.envelope.clearedBefore, env.clearedBefore)
    }

    func test_decode_garbageReturnsNil() {
        XCTAssertNil(Env.decode(Data("nope".utf8)))
    }

    func test_markCleared_onlyMovesForward() {
        var env = Env()
        env.markCleared(at: now)
        env.markCleared(at: now.addingTimeInterval(-10))
        XCTAssertEqual(env.clearedBefore, now)
    }

    func test_markDeleted_replacesExistingTombstone() {
        let id = UUID()
        var env = Env()
        env.markDeleted([id], at: now.addingTimeInterval(-5))
        env.markDeleted([id], at: now)
        XCTAssertEqual(env.deleted.count, 1)
        XCTAssertEqual(env.deleted.first?.at, now)
    }

    func test_carriesContent() {
        let x = item()
        let shared = Env(items: [x])
        XCTAssertTrue(Env(items: [x]).carriesContent(missingFrom: Env()))
        let tomb = CloudTombstone(id: UUID(), at: now)
        XCTAssertTrue(Env(deleted: [tomb]).carriesContent(missingFrom: Env()))
        XCTAssertTrue(Env(clearedBefore: now).carriesContent(missingFrom: Env(clearedBefore: now.addingTimeInterval(-1))))
        XCTAssertFalse(shared.carriesContent(missingFrom: shared))
    }
}
