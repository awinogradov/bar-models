import Foundation

/// Streaming reader for JSON Lines files.
///
/// Reads in fixed chunks and yields each complete line as `Data` via a callback,
/// so a 500 MB tree is never loaded whole. A trailing partial line (no newline
/// yet — common while Claude Code is actively writing) is **not** yielded, and
/// the returned offset stops at the start of that partial, so an incremental
/// rescan can resume cleanly from `seek(toOffset:)`.
public enum JSONLReader {
    /// Reads complete lines from `url` starting at byte `offset`, invoking
    /// `onLine` for each (without the trailing `\n`). Returns the byte offset of
    /// the first unconsumed byte (i.e. the start of any trailing partial line).
    @discardableResult
    public static func readLines(
        from url: URL,
        startingAt offset: UInt64 = 0,
        chunkSize: Int = 256 * 1024,
        onLine: (Data) -> Void
    ) throws -> UInt64 {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        if offset > 0 { try handle.seek(toOffset: offset) }

        let newline: UInt8 = 0x0A
        var buffer = Data()
        var consumed = offset

        while let chunk = try handle.read(upToCount: chunkSize), !chunk.isEmpty {
            buffer.append(chunk)
            while let nl = buffer.firstIndex(of: newline) {
                let line = buffer.subdata(in: buffer.startIndex..<nl)
                onLine(line)
                let advance = buffer.distance(from: buffer.startIndex, to: nl) + 1
                consumed += UInt64(advance)
                buffer.removeSubrange(buffer.startIndex...nl)
            }
        }
        return consumed
    }
}
