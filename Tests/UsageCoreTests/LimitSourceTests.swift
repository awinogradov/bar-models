import Testing
import Foundation
@testable import UsageCore

@Suite("LimitSource")
struct LimitSourceTests {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    /// Writes a snapshot JSON to a unique temp file and returns a `LimitSource` for it.
    private func source(_ json: String, freshness: TimeInterval = 15 * 60) throws -> LimitSource {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("limitsrc-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("snapshot.json")
        try json.write(to: url, atomically: true, encoding: .utf8)
        return LimitSource(url: url, freshness: freshness)
    }

    private func snapshot(fiveHour: Double? = nil, sevenDay: Double? = nil,
                          fhReset: Double? = nil, sdReset: Double? = nil, ts: Double) -> String {
        var parts = ["\"ts\": \(ts)"]
        if let fiveHour { parts.append("\"five_hour\": \(fiveHour)") }
        if let sevenDay { parts.append("\"seven_day\": \(sevenDay)") }
        if let fhReset { parts.append("\"five_hour_resets_at\": \(fhReset)") }
        if let sdReset { parts.append("\"seven_day_resets_at\": \(sdReset)") }
        return "{" + parts.joined(separator: ", ") + "}"
    }

    @Test("fresh snapshot yields official 0…1 percentages")
    func fresh() throws {
        let src = try source(snapshot(fiveHour: 42, sevenDay: 31, ts: now.timeIntervalSince1970))
        let limits = src.read(now: now)
        #expect(limits.fiveHour?.isOfficial == true)
        #expect(limits.fiveHour?.available == true)
        #expect(limits.fiveHour?.basis == "official")
        #expect(abs((limits.fiveHour?.percent ?? -1) - 0.42) < 1e-9)
        #expect(abs((limits.weekly?.percent ?? -1) - 0.31) < 1e-9)
    }

    @Test("freshness boundary uses <= (exact age is fresh, one second older is stale)")
    func freshnessBoundary() throws {
        let f: TimeInterval = 900
        let atBoundary = try source(snapshot(fiveHour: 10, ts: now.timeIntervalSince1970 - f), freshness: f)
        #expect(atBoundary.read(now: now).fiveHour != nil)

        let justInside = try source(snapshot(fiveHour: 10, ts: now.timeIntervalSince1970 - f + 1), freshness: f)
        #expect(justInside.read(now: now).fiveHour != nil)

        let justStale = try source(snapshot(fiveHour: 10, ts: now.timeIntervalSince1970 - f - 1), freshness: f)
        #expect(justStale.read(now: now).fiveHour == nil)
        #expect(justStale.read(now: now).weekly == nil)
    }

    @Test("an absent window is nil; the present one stays official")
    func absentWindow() throws {
        let src = try source(snapshot(fiveHour: 50, ts: now.timeIntervalSince1970))
        let limits = src.read(now: now)
        #expect(limits.fiveHour != nil)
        #expect(limits.weekly == nil)
    }

    @Test("a window whose resets_at has passed is dropped; a future reset is kept")
    func resetCrossing() throws {
        let passed = try source(snapshot(fiveHour: 90, fhReset: now.timeIntervalSince1970 - 1,
                                         ts: now.timeIntervalSince1970))
        #expect(passed.read(now: now).fiveHour == nil)

        let future = try source(snapshot(fiveHour: 90, fhReset: now.timeIntervalSince1970 + 1,
                                         ts: now.timeIntervalSince1970))
        #expect(future.read(now: now).fiveHour != nil)
    }

    @Test("missing file and malformed JSON read as empty")
    func malformed() throws {
        let missing = LimitSource(url: FileManager.default.temporaryDirectory
            .appendingPathComponent("does-not-exist-\(UUID().uuidString).json"))
        #expect(missing.read(now: now) == OfficialLimits())

        let garbage = try source("not json at all")
        #expect(garbage.read(now: now) == OfficialLimits())
    }

    @Test("0–100 maps to 0…1, over-100 passes through, negative is nil")
    func conversions() throws {
        let zero = try source(snapshot(fiveHour: 0, ts: now.timeIntervalSince1970))
        #expect(zero.read(now: now).fiveHour?.percent == 0.0)

        let full = try source(snapshot(fiveHour: 100, ts: now.timeIntervalSince1970))
        #expect(full.read(now: now).fiveHour?.percent == 1.0)

        let over = try source(snapshot(fiveHour: 105, ts: now.timeIntervalSince1970))
        #expect(abs((over.read(now: now).fiveHour?.percent ?? -1) - 1.05) < 1e-9)

        let negative = try source(snapshot(fiveHour: -5, ts: now.timeIntervalSince1970))
        #expect(negative.read(now: now).fiveHour == nil)
    }
}
