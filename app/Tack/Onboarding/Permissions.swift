import AppKit
import ApplicationServices

/// Live state of the two permissions Tack needs, refreshed by polling while someone is waiting on it
/// (macOS sends no notification when the user flips a switch in System Settings).
@MainActor
@Observable
final class Permissions {
    enum Kind: String {
        case screenRecording = "Privacy_ScreenCapture"
        case accessibility = "Privacy_Accessibility"
    }

    private(set) var screenRecording = CGPreflightScreenCaptureAccess()
    private(set) var accessibility = AXIsProcessTrusted()

    var allGranted: Bool { screenRecording && accessibility }

    @ObservationIgnored private var timer: Timer?

    func refresh() {
        let screen = CGPreflightScreenCaptureAccess()
        let ax = AXIsProcessTrusted()
        if screen != screenRecording {
            screenRecording = screen
            tackLog("permission: Screen Recording \(screen ? "granted" : "not granted")")
        }
        if ax != accessibility {
            accessibility = ax
            tackLog("permission: Accessibility \(ax ? "granted" : "not granted")")
        }
    }

    func startWatching() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    func stopWatching() {
        timer?.invalidate()
        timer = nil
    }

    /// The first time, macOS's own prompt adds Tack to the list in System Settings and offers to open it.
    /// macOS only shows that prompt once per app, so after that we also open the right pane directly. We still ask
    /// every time: if Tack was removed from the list (a reset, say), asking is what puts it back.
    func request(_ kind: Kind) {
        let key = "requested.\(kind.rawValue)"
        let askedBefore = UserDefaults.standard.bool(forKey: key)
        UserDefaults.standard.set(true, forKey: key)
        switch kind {
        case .screenRecording:
            CGRequestScreenCaptureAccess()
        case .accessibility:
            AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
        }
        if askedBefore { openSettings(kind) }
    }

    func openSettings(_ kind: Kind) {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?\(kind.rawValue)")!)
    }

    /// Screen Recording can need a restart before macOS reports it as granted.
    func relaunch() {
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: config) { _, _ in
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }
}
