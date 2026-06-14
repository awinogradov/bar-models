import SwiftUI

/// The menu-bar scene. Shows one value (M1: Tokens · This Month · input+output)
/// in the menu bar with a small dropdown. Not `@main` — `Main` dispatches to it.
struct BarModelsApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            MenuContentView(model: model)
        } label: {
            Text(model.title).foregroundStyle(model.titleLevel.tint)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(model: model)
        }
    }
}

private extension LimitLevel {
    /// Menu-bar tint: normal text, amber past 80%, red past 100%.
    var tint: Color {
        switch self {
        case .normal: .primary
        case .warn: .orange
        case .over: .red
        }
    }
}
