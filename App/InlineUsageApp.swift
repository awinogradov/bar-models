import SwiftUI

/// The menu-bar scene. Shows one value (M1: Tokens · This Month · input+output)
/// in the menu bar with a small dropdown. Not `@main` — `Main` dispatches to it.
struct InlineUsageApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            MenuContentView(model: model)
        } label: {
            Text(model.title)
        }
        .menuBarExtraStyle(.window)
    }
}
