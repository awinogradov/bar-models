import Combine
import Sparkle
import SwiftUI

/// Owns the Sparkle updater for the app's lifetime.
///
/// The feed and signing configuration (`SUFeedURL`, `SUPublicEDKey`,
/// `SUEnableAutomaticChecks`) live in the bundle's `Info.plist` — written by
/// `scripts/package-app.sh` — so there is nothing to configure programmatically
/// here. `canCheckForUpdates` is republished from the updater so the menu item
/// can disable itself while a check or install is already in flight.
@MainActor
final class UpdaterController: ObservableObject {
    @Published private(set) var canCheckForUpdates = false

    private let controller: SPUStandardUpdaterController

    init() {
        // startingUpdater: true → begins scheduled checks immediately (gated by
        // the user's consent prompt on first launch and SUEnableAutomaticChecks).
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        controller.updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)
    }

    /// The underlying Sparkle updater, for settings that read/write its prefs.
    var updater: SPUUpdater { controller.updater }

    /// Run a user-initiated check (shows Sparkle's progress + update UI).
    func checkForUpdates() {
        controller.updater.checkForUpdates()
    }
}
