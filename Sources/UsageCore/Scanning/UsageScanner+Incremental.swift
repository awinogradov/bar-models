import Foundation

/// Incremental scanning: a refresh re-stats every file but only *reads* new or
/// grown ones, resuming from the saved byte offset. After the first (full) pass,
/// a refresh triggered by one new turn touches ~1 file and a few KB — cheap
/// enough to run on every filesystem change.
public extension UsageScanner {
    /// Update accumulated state across all registered providers.
    func update(_ state: ScanState) -> ScanState {
        var next = state
        for provider in registry.providers {
            next = updateState(next, roots: provider.dataRoots(), provider: provider)
        }
        return next
    }

    /// Update state for explicit roots + provider (also the unit-test entry point).
    func updateState(_ state: ScanState, roots: [URL], provider: any UsageProvider) -> ScanState {
        var files = state.files
        var events = state.events
        let fm = FileManager.default

        for root in roots {
            for url in UsageScanner.jsonlFiles(under: root) {
                let path = url.path
                let attrs = try? fm.attributesOfItem(atPath: path)
                let size = (attrs?[.size] as? NSNumber)?.uint64Value ?? 0
                let mtime = (attrs?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
                let inode = (attrs?[.systemFileNumber] as? NSNumber)?.uint64Value
                let createdAt = (attrs?[.creationDate] as? Date)?.timeIntervalSince1970

                let prior = files[path]
                if let prior, prior.size == size, prior.modified == mtime,
                   prior.inode == inode, prior.createdAt == createdAt {
                    continue // unchanged → skip
                }
                // Same file that only grew → resume from the saved offset. A new,
                // shrunk, or replaced file re-reads from 0 — including a rotation that
                // reused the inode after a delete+create, which the birthtime catches.
                let sameFile = prior.map { $0.inode == inode && $0.createdAt == createdAt } ?? false
                let start: UInt64 = (sameFile && size >= (prior?.size ?? 0)) ? (prior?.offset ?? 0) : 0
                let newOffset = (try? JSONLReader.readLines(from: url, startingAt: start) { line in
                    if let event = provider.parse(line: line) {
                        events["\(event.provider.rawValue)\u{1}\(event.id)"] = event
                    }
                }) ?? start
                files[path] = FileScanState(size: size, modified: mtime, offset: newOffset, inode: inode, createdAt: createdAt)
            }
        }
        return ScanState(files: files, events: events)
    }
}
