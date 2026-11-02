import AppKit
import Sparkle

/// Update checks (Sparkle). Off by default: Tack only goes online if the user turns this on or chooses
/// Check for Updates. Sparkle remembers the choice itself.
@MainActor
@Observable
final class Updates {
    @ObservationIgnored private let controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)

    var checksAutomatically: Bool {
        didSet { controller.updater.automaticallyChecksForUpdates = checksAutomatically }
    }

    init() {
        checksAutomatically = controller.updater.automaticallyChecksForUpdates
    }

    func check() {
        // An agent app isn't active by default, so Sparkle's window would open behind whatever the user is in.
        NSApp.activate()
        controller.checkForUpdates(nil)
    }
}
