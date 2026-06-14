import Foundation
import OSLog
import UsageCore

/// Installs and removes the bar-models status-line hook in the user's Claude Code
/// configuration. This is the only place the app writes under `~/.claude`, and only
/// on explicit opt-in. Every `settings.json` write is atomic and preceded by a
/// one-time backup; disable verifies the hook is still ours before touching anything,
/// so a status line the user changed by hand is left alone. The pure JSON transform
/// lives in `UsageCore.StatusLineConfig`; this is the file IO around it.
@MainActor
enum LiveLimits {
    private static let log = Logger(subsystem: "bar-models", category: "LiveLimits")
    private static let fm = FileManager.default
    private static var home: URL { fm.homeDirectoryForCurrentUser }

    static var directory: URL { home.appendingPathComponent(".claude/bar-models") }
    static var scriptURL: URL { directory.appendingPathComponent("bar-models-statusline.sh") }
    private static var wrappedCommandURL: URL { directory.appendingPathComponent("wrapped-command") }
    private static var previousStatusLineURL: URL { directory.appendingPathComponent("previous-statusline.json") }
    private static var settingsURL: URL { home.appendingPathComponent(".claude/settings.json") }
    private static var backupURL: URL { home.appendingPathComponent(".claude/settings.json.bak") }

    enum DisableOutcome { case restored, leftAlone }
    enum InstallError: LocalizedError {
        case scriptNotFound
        var errorDescription: String? { "Could not find the bundled status-line script." }
    }

    /// `jq` (the script's dependency) is resolvable on a common path.
    static var jqAvailable: Bool {
        ["/opt/homebrew/bin/jq", "/usr/local/bin/jq", "/usr/bin/jq", "/bin/jq"]
            .contains { fm.isExecutableFile(atPath: $0) }
    }

    /// Install the hook and register it as the `statusLine` command, wrapping any
    /// existing one. Throws (so the caller can revert the toggle) on any IO/parse failure.
    static func enable() throws {
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        try installScript()

        let current = try? Data(contentsOf: settingsURL)
        if let current, !fm.fileExists(atPath: backupURL.path) {
            try current.write(to: backupURL, options: .atomic) // one-time safety net
        }

        let result = try StatusLineConfig.enable(settings: current, scriptCommand: scriptURL.path)
        try write(result.priorCommand.map { Data($0.utf8) }, to: wrappedCommandURL)
        try write(result.priorStatusLine, to: previousStatusLineURL)
        try result.settings.write(to: settingsURL, options: .atomic)
    }

    /// Restore the user's prior status line (or remove ours), but only when our hook
    /// is still the installed command — otherwise leave settings untouched.
    @discardableResult
    static func disable() throws -> DisableOutcome {
        defer {
            try? fm.removeItem(at: wrappedCommandURL)
            try? fm.removeItem(at: previousStatusLineURL)
        }
        guard let current = try? Data(contentsOf: settingsURL) else { return .restored }
        guard installedCommand(in: current) == scriptURL.path else {
            log.notice("statusLine no longer points at our hook; leaving settings.json untouched")
            return .leftAlone
        }
        let prior = try? Data(contentsOf: previousStatusLineURL)
        let restored = try StatusLineConfig.disable(settings: current, priorStatusLine: prior)
        try restored.write(to: settingsURL, options: .atomic)
        return .restored
    }

    // MARK: - Helpers

    private static func installScript() throws {
        guard let source = bundledScriptURL() else { throw InstallError.scriptNotFound }
        let contents = try Data(contentsOf: source)
        try contents.write(to: scriptURL, options: .atomic) // fresh write → no quarantine xattr travels
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)
    }

    /// The packaged `.app` ships the script in `Contents/Resources`; `swift run`
    /// falls back to the repo copy relative to the working directory.
    private static func bundledScriptURL() -> URL? {
        if let url = Bundle.main.url(forResource: "bar-models-statusline", withExtension: "sh") {
            return url
        }
        let devURL = URL(fileURLWithPath: fm.currentDirectoryPath)
            .appendingPathComponent("scripts/bar-models-statusline.sh")
        return fm.fileExists(atPath: devURL.path) ? devURL : nil
    }

    private static func installedCommand(in data: Data) -> String? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let statusLine = root["statusLine"] as? [String: Any] else { return nil }
        return statusLine["command"] as? String
    }

    private static func write(_ data: Data?, to url: URL) throws {
        if let data {
            try data.write(to: url, options: .atomic)
        } else {
            try? fm.removeItem(at: url)
        }
    }
}
