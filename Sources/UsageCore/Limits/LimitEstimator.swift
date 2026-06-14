import Foundation

/// Optional custom budgets (billable tokens) that override the estimate.
public struct LimitBudgets: Sendable, Equatable {
    public var fiveHour: UInt64?
    public var weekly: UInt64?
    public init(fiveHour: UInt64? = nil, weekly: UInt64? = nil) {
        self.fiveHour = fiveHour
        self.weekly = weekly
    }
}

/// Estimates "% of plan limit" without knowing Anthropic's (unpublished) token
/// budgets. The honest calibration is **your own history**: the budget defaults
/// to the P90 of past windows, so the percentage means "how close to your typical
/// peak". Always flagged as an estimate; superseded by the official status-line
/// value in M4 when available. Uses `billableTotal` (what Anthropic meters).
public struct LimitEstimator: Sendable {
    public static let week: TimeInterval = 7 * 24 * 3600

    private let windower = FiveHourWindower()

    public init() {}

    /// 5-hour window: usage in the active block ÷ P90 of historical blocks.
    public func fiveHour(_ events: [UsageEvent], now: Date, customBudget: UInt64? = nil) -> LimitStatus {
        let valid = events.filter { $0.timestamp <= now }
        let blocks = windower.blocks(valid)
        let used = blocks.last.map { now.timeIntervalSince($0.start) < FiveHourWindower.window ? $0.usage : 0 } ?? 0
        return status(used: used, custom: customBudget, history: blocks.map(\.usage), basis: "est · P90 of \(blocks.count) blocks")
    }

    /// Weekly window: rolling 7-day usage ÷ P90 of historical 7-day rolling sums.
    public func weekly(_ events: [UsageEvent], now: Date, customBudget: UInt64? = nil) -> LimitStatus {
        let valid = events.filter { $0.timestamp <= now }.sorted { $0.timestamp < $1.timestamp }
        let cutoff = now.addingTimeInterval(-Self.week)
        let used = valid.reduce(UInt64(0)) { $1.timestamp > cutoff ? $0 &+ $1.tokens.billableTotal : $0 }
        return status(used: used, custom: customBudget, history: Self.rollingSums(valid, window: Self.week), basis: "est · P90 of weekly load")
    }

    private func status(used: UInt64, custom: UInt64?, history: [UInt64], basis: String) -> LimitStatus {
        if let c = custom, c > 0 {
            return LimitStatus(percent: Double(used) / Double(c), isOfficial: false, available: true, basis: "est · custom budget")
        }
        guard let budget = Self.p90(history.filter { $0 > 0 }), budget > 0 else {
            return LimitStatus(available: false, basis: "no history")
        }
        return LimitStatus(percent: Double(used) / Double(budget), isOfficial: false, available: true, basis: basis)
    }

    /// Running sum of `billableTotal` over a trailing time window, evaluated at each
    /// event (two-pointer, O(n)) — the distribution of historical window loads.
    static func rollingSums(_ sorted: [UsageEvent], window: TimeInterval) -> [UInt64] {
        var sums: [UInt64] = []
        var lo = 0
        var running: UInt64 = 0
        for hi in sorted.indices {
            running &+= sorted[hi].tokens.billableTotal
            while sorted[hi].timestamp.timeIntervalSince(sorted[lo].timestamp) > window {
                running &-= sorted[lo].tokens.billableTotal
                lo += 1
            }
            sums.append(running)
        }
        return sums
    }

    static func p90(_ xs: [UInt64]) -> UInt64? {
        guard !xs.isEmpty else { return nil }
        let sorted = xs.sorted()
        return sorted[Int((Double(sorted.count - 1) * 0.9).rounded())]
    }
}
