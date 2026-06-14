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

                if let prior = files[path], prior.size == size, prior.modified == mtime {
                    continue // unchanged → skip
                }
                // Grew → resume from saved offset; new / shrank / rotated → re-read from 0.
                let start: UInt64 = files[path].map { size >= $0.size ? $0.offset : 0 } ?? 0
                let newOffset = (try? JSONLReader.readLines(from: url, startingAt: start) { line in
                    if let event = provider.parse(line: line) {
                        events["\(event.provider.rawValue)\u{1}\(event.id)"] = event
                    }
                }) ?? start
                files[path] = FileScanState(size: size, modified: mtime, offset: newOffset)
            }
        }
        return ScanState(files: files, events: events)
    }
}
