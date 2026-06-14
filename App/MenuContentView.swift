import SwiftUI
import UsageCore

/// The dropdown shown when the menu-bar item is clicked. M1: the current value,
/// breakdown, refresh, and quit. The fast-switch metric list lands in M2.
struct MenuContentView: View {
    let model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if model.hasData {
                Text("Tokens · This Month")
                    .font(.headline)
                Text(model.exactThisMonth)
                    .font(.system(.title2, design: .rounded).monospacedDigit())
                Text(model.breakdownThisMonth)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Label("Loading…", systemImage: "hourglass")
                    .foregroundStyle(.secondary)
            }

            Divider()

            Button("Refresh") { model.refresh() }
            Button("Quit") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q")
        }
        .padding(12)
        .frame(width: 260)
    }
}
