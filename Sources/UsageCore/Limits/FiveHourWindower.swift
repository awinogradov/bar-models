import Foundation

/// Groups events into Anthropic-style 5-hour blocks: a block starts at the first
/// activity and lasts exactly 5 hours; the next event after it opens a new block.
/// (This mirrors how the session window resets, unlike a pure rolling sum.)
public struct FiveHourWindower: Sendable {
    public static let window: TimeInterval = 5 * 3600

    public init() {}

    /// Per-block `(start, billable-token usage)`, in chronological order.
    public func blocks(_ events: [UsageEvent]) -> [(start: Date, usage: UInt64)] {
        let sorted = events.sorted { $0.timestamp < $1.timestamp }
        var result: [(start: Date, usage: UInt64)] = []
        var start: Date?
        var sum: UInt64 = 0
        for event in sorted {
            if let s = start, event.timestamp.timeIntervalSince(s) < Self.window {
                sum &+= event.tokens.billableTotal
            } else {
                if let s = start { result.append((start: s, usage: sum)) }
                start = event.timestamp
                sum = event.tokens.billableTotal
            }
        }
        if let s = start { result.append((start: s, usage: sum)) }
        return result
    }
}
