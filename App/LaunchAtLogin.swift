import OSLog
import ServiceManagement

/// Thin wrapper over `SMAppService.mainApp` (macOS 13+) for the launch-at-login
/// toggle. Registration only succeeds for a signed, bundled `.app` launched from
/// a stable location — running unbundled via `swift run` makes `register()` throw,
/// so every call is best-effort and the resulting `status` is the source of truth.
@MainActor
enum LaunchAtLogin {
    private static let log = Logger(subsystem: "inline-usage", category: "LaunchAtLogin")

    /// `true` only when the system reports the login item as enabled.
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    /// Registers or unregisters the app as a login item; returns the *actual*
    /// resulting state (which may differ from the request — e.g. the user has to
    /// approve it in System Settings, or a dev build can't register at all).
    @discardableResult
    static func setEnabled(_ enabled: Bool) -> Bool {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else if SMAppService.mainApp.status != .notRegistered {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            log.error("launch-at-login \(enabled ? "register" : "unregister") failed: \(error.localizedDescription)")
        }
        return isEnabled
    }
}
