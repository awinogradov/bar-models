import Foundation

/// Pure transforms over the JSON of `~/.claude/settings.json` for installing and
/// removing the bar-models status-line hook. Kept free of file IO so it is fully
/// unit-testable; the app performs the (atomic, backed-up) reads and writes.
///
/// Safety contract: every sibling key is preserved, an already-installed hook is a
/// no-op (idempotent), and unparseable settings throw rather than being overwritten
/// — the app must never clobber a config it cannot model.
public enum StatusLineConfig {
    public struct EnableResult: Sendable {
        /// Settings JSON with our hook installed as the `statusLine` command.
        public var settings: Data
        /// The entire prior `statusLine` value (wrapped), for an exact restore on disable; `nil` if none or already ours.
        public var priorStatusLine: Data?
        /// The prior `command` string (when the prior `statusLine` was a command), for the script's pass-through; `nil` otherwise.
        public var priorCommand: String?
    }

    public enum ConfigError: Error { case unreadable }

    /// Install `scriptCommand` as the `statusLine` command, wrapping any existing one.
    public static func enable(settings: Data?, scriptCommand: String) throws -> EnableResult {
        var root = try object(from: settings)
        let prior = root["statusLine"]

        // Idempotent: already pointing at our script → no change, no priors to save.
        if let dict = prior as? [String: Any], dict["command"] as? String == scriptCommand {
            return EnableResult(settings: try serialize(root), priorStatusLine: nil, priorCommand: nil)
        }

        var priorStatusLine: Data?
        var priorCommand: String?
        if let prior {
            // Wrap the prior value so any shape (object/string) round-trips without fragment options.
            priorStatusLine = try JSONSerialization.data(withJSONObject: ["statusLine": prior], options: [.sortedKeys])
            if let dict = prior as? [String: Any],
               dict["type"] as? String == "command",
               let cmd = dict["command"] as? String {
                priorCommand = cmd
            }
        }

        root["statusLine"] = ["type": "command", "command": scriptCommand]
        return EnableResult(settings: try serialize(root), priorStatusLine: priorStatusLine, priorCommand: priorCommand)
    }

    /// Restore the saved prior `statusLine`, or remove it entirely when there was none.
    public static func disable(settings: Data, priorStatusLine: Data?) throws -> Data {
        var root = try object(from: settings)
        if let priorStatusLine,
           let wrapper = try? JSONSerialization.jsonObject(with: priorStatusLine) as? [String: Any],
           let restored = wrapper["statusLine"] {
            root["statusLine"] = restored
        } else {
            root.removeValue(forKey: "statusLine")
        }
        return try serialize(root)
    }

    private static func object(from data: Data?) throws -> [String: Any] {
        guard let data, !data.isEmpty else { return [:] }
        guard let obj = try? JSONSerialization.jsonObject(with: data), let dict = obj as? [String: Any] else {
            throw ConfigError.unreadable
        }
        return dict
    }

    private static func serialize(_ root: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
    }
}
