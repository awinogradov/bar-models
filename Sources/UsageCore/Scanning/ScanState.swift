import Foundation

/// Per-file cursor for incremental scanning: skip files whose size+mtime are
/// unchanged, and resume a grown file from `offset` instead of re-reading it.
public struct FileScanState: Sendable, Codable, Equatable {
    public var size: UInt64
    public var modified: TimeInterval
    public var offset: UInt64

    public init(size: UInt64, modified: TimeInterval, offset: UInt64) {
        self.size = size
        self.modified = modified
        self.offset = offset
    }
}

/// Accumulated scan state carried across refreshes: per-file cursors plus the
/// deduped event map (keyed by `(provider, message.id)`). Value type so it can
/// be handed to an off-main task and returned. (M4 persists this across launches.)
public struct ScanState: Sendable {
    public var files: [String: FileScanState]
    public var events: [String: UsageEvent]

    public init(files: [String: FileScanState] = [:], events: [String: UsageEvent] = [:]) {
        self.files = files
        self.events = events
    }

    public var allEvents: [UsageEvent] { Array(events.values) }
}
