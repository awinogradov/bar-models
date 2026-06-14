import Foundation

/// Claude Code's official rate-limit reading, captured by the status-line hook
/// (`scripts/bar-models-statusline.sh`) into `~/.claude/bar-models/snapshot.json`.
/// Lenient on purpose: every field except `ts` is optional, so a free-plan session
/// (no `rate_limits`) or a partial write decodes without throwing. Percentages are
/// Claude Code's native 0–100 scale; `*ResetsAt` are epoch seconds for the window
/// reset (when reported), used to discard a reading whose window has since rolled.
struct OfficialSnapshot: Codable, Sendable {
    var fiveHour: Double?
    var sevenDay: Double?
    var fiveHourResetsAt: Double?
    var sevenDayResetsAt: Double?
    var model: String?
    var ts: Double

    enum CodingKeys: String, CodingKey {
        case fiveHour = "five_hour"
        case sevenDay = "seven_day"
        case fiveHourResetsAt = "five_hour_resets_at"
        case sevenDayResetsAt = "seven_day_resets_at"
        case model
        case ts
    }
}

/// The official 5-hour and weekly readings, each `nil` when unavailable for that
/// window. A `nil` window is the contract that lets the `Aggregator` fall back to
/// the estimate via `official ?? estimate` — callers must never substitute an
/// empty `LimitStatus`, or the estimate would be silently dropped.
public struct OfficialLimits: Sendable, Equatable {
    public var fiveHour: LimitStatus?
    public var weekly: LimitStatus?

    public init(fiveHour: LimitStatus? = nil, weekly: LimitStatus? = nil) {
        self.fiveHour = fiveHour
        self.weekly = weekly
    }
}

/// Reads the official-limit snapshot the status-line hook writes. The estimate
/// (`LimitEstimator`) remains the fallback; this only supersedes it when a fresh,
/// non-reset reading exists. `url` and `freshness` are injectable for tests.
public struct LimitSource: Sendable {
    public let url: URL
    public let freshness: TimeInterval

    /// `~/.claude/bar-models/snapshot.json` — mirrors `ClaudeProvider`'s home-dir resolution.
    public static var defaultURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/bar-models/snapshot.json")
    }

    public init(url: URL = LimitSource.defaultURL, freshness: TimeInterval = 15 * 60) {
        self.url = url
        self.freshness = freshness
    }

    /// Official limits as of `now`, or empty when the snapshot is missing, malformed,
    /// older than `freshness`, or its windows have reset. Per window: `nil` if the
    /// percentage is absent/negative/non-finite, or if `resetsAt` has passed.
    public func read(now: Date) -> OfficialLimits {
        guard let data = try? Data(contentsOf: url),
              let snap = try? JSONDecoder().decode(OfficialSnapshot.self, from: data)
        else { return OfficialLimits() }

        let nowEpoch = now.timeIntervalSince1970
        guard nowEpoch - snap.ts <= freshness else { return OfficialLimits() }

        func status(_ percent: Double?, resetsAt: Double?) -> LimitStatus? {
            guard let percent, percent.isFinite, percent >= 0 else { return nil }
            if let resetsAt, nowEpoch >= resetsAt { return nil } // window rolled since the reading
            return LimitStatus(percent: percent / 100, isOfficial: true, available: true, basis: "official")
        }

        return OfficialLimits(
            fiveHour: status(snap.fiveHour, resetsAt: snap.fiveHourResetsAt),
            weekly: status(snap.sevenDay, resetsAt: snap.sevenDayResetsAt)
        )
    }
}
