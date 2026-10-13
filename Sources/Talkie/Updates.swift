import AppKit
import Sparkle

/// Keeps Talkie up to date with Sparkle: checks the update feed now and then (and on request),
/// and offers each new build. Updates are signed; Talkie only installs ones signed with the key
/// in Info.plist (SUPublicEDKey).
@MainActor
final class Updates: NSObject, SPUStandardUserDriverDelegate {
    private var controller: SPUStandardUpdaterController?

    func start() {
        controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: self)
    }

    @objc func checkForUpdates() {
        NSApp.activate()
        controller?.checkForUpdates(nil)
    }

    // Talkie lives in the menu bar and is rarely the app in front, so when a scheduled check finds an
    // update, bring Talkie forward and show it rather than leaving the window behind other apps.
    nonisolated var supportsGentleScheduledUpdateReminders: Bool { true }

    nonisolated func standardUserDriverShouldHandleShowingScheduledUpdate(_ update: SUAppcastItem, andInImmediateFocus immediateFocus: Bool) -> Bool {
        true
    }

    nonisolated func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState) {
        guard handleShowingUpdate else { return }
        Task { @MainActor in NSApp.activate() }
    }
}
