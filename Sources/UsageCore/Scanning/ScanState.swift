import Foundation

/// Per-file cursor for incremental scanning: skip files whose size+mtime are
/// unchanged, and resume a grown file from `offset` instead of re-reading it.
/// `inode` + `createdAt` identify the file across launches, so a rotated or
/// replaced file — even one that reuses the inode — is detected and re-read
/// from offset 0 rather than resumed into the middle of new content.
public struct FileScanState: Sendable, Codable, Equatable {
    public var size: UInt64
    public var modified: TimeInterval
    public var offset: UInt64
    /// Filesystem identity (`systemFileNumber`); optional for forward-compatibility.
    public var inode: UInt64?
    /// File creation time (APFS birthtime); distinguishes an inode-reused replacement.
    public var createdAt: TimeInterval?

    public init(size: UInt64, modified: TimeInterval, offset: UInt64, inode: UInt64? = nil, createdAt: TimeInterval? = nil) {
        self.size = size
        self.modified = modified
        self.offset = offset
        self.inode = inode
        self.createdAt = createdAt
    }
}

/// Accumulated scan state carried across refreshes: per-file cursors plus the
/// deduped event map (keyed by `(provider, message.id)`). Value type so it can
/// be handed to an off-main task and returned. (M4 persists this across launches.)
public struct ScanState: Sendable, Codable, Equatable {
    public var files: [String: FileScanState]
    public var events: [String: UsageEvent]

    public init(files: [String: FileScanState] = [:], events: [String: UsageEvent] = [:]) {
        self.files = files
        self.events = events
    }

    public var allEvents: [UsageEvent] { Array(events.values) }
}
