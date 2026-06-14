import Foundation

/// How often the menu bar refreshes. Real-time relies on filesystem events;
/// the interval options add a periodic refresh on top.
enum RefreshInterval: String, CaseIterable, Sendable {
    case realtime, s1, s2, s5, s10, s30

    var seconds: TimeInterval? {
        switch self {
        case .realtime: nil
        case .s1: 1
        case .s2: 2
        case .s5: 5
        case .s10: 10
        case .s30: 30
        }
    }

    var label: String {
        switch self {
        case .realtime: "Real-time"
        case .s1: "Every 1 second"
        case .s2: "Every 2 seconds"
        case .s5: "Every 5 seconds"
        case .s10: "Every 10 seconds"
        case .s30: "Every 30 seconds"
        }
    }
}

/// Watches the providers' data roots with FSEvents and fires a debounced refresh
/// when files change, so new usage appears within a fraction of a second. With
/// the incremental scanner each refresh reads only appended bytes. An optional
/// interval timer adds periodic refreshes (and advances rolling windows when idle).
@MainActor
final class RefreshController {
    private let onChange: @MainActor () -> Void
    private var stream: FSEventStreamRef?
    private var timer: Timer?
    private var debounce: Task<Void, Never>?

    init(onChange: @escaping @MainActor () -> Void) {
        self.onChange = onChange
    }

    func start(roots: [URL], interval: RefreshInterval) {
        stop()
        startWatching(roots)
        if let seconds = interval.seconds {
            timer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.onChange() }
            }
        }
    }

    func stop() {
        if let stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            self.stream = nil
        }
        timer?.invalidate()
        timer = nil
        debounce?.cancel()
        debounce = nil
    }

    private func startWatching(_ roots: [URL]) {
        let paths = roots.map(\.path)
        guard !paths.isEmpty else { return }

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        // C callback: no captures (only its params), so it converts to a C function pointer.
        let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info else { return }
            let controller = Unmanaged<RefreshController>.fromOpaque(info).takeUnretainedValue()
            Task { @MainActor in controller.scheduleRefresh() }
        }
        let flags = UInt32(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer)
        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            callback,
            &context,
            paths as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.3, // coalescing latency (seconds)
            flags
        ) else { return }

        self.stream = stream
        FSEventStreamSetDispatchQueue(stream, DispatchQueue.global(qos: .utility))
        FSEventStreamStart(stream)
    }

    private func scheduleRefresh() {
        debounce?.cancel()
        let onChange = self.onChange
        debounce = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            onChange()
        }
    }
}
