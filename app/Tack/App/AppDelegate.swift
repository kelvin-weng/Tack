import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let permissions = Permissions()
    private let pins = PinManager()
    private let updates = Updates()
    private var menuBar: MenuBarController?
    private lazy var hotKey = HotKey { [weak self] in self?.togglePin() }
    private var notch: NotchController?
    private lazy var onboarding = OnboardingWindowController(permissions: permissions, hotKey: hotKey)
    private lazy var settings = SettingsWindowController(hotKey: hotKey, updates: updates)

    func applicationDidFinishLaunching(_ notification: Notification) {
        PinSettings.registerDefaults()
        tackLog("launch: Screen Recording \(permissions.screenRecording), Accessibility \(permissions.accessibility), onboarding completed \(Onboarding.completed)")
        menuBar = MenuBarController(
            openSettings: { [weak self] in self?.settings.show() },
            openOnboarding: { [weak self] in self?.onboarding.show() },
            checkForUpdates: { [weak self] in self?.updates.check() },
            togglePin: { [weak self] in self?.togglePin() },
            permissions: permissions,
            pins: pins,
            hotKey: hotKey
        )
        pins.onChange = { [weak self] in self?.notch?.update() }
        setUpNotch()
        // Lid closed with an external display, display unplugged, resolution changed: the notch may come or go.
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.setUpNotch() }
        }
        if Onboarding.needsToShow(permissions: permissions) {
            onboarding.show()
        }
    }

    /// The notch panel exists only while a notched screen is connected; the menu bar always works.
    private func setUpNotch() {
        notch?.tearDown()
        notch = NotchController(pins: pins)
    }

    private func togglePin() {
        permissions.refresh()
        guard permissions.allGranted else {
            onboarding.show()
            return
        }
        pins.toggleFrontmost()
    }

    /// Opening Tack again from Finder or Launchpad while it's running shows Settings, since there's no Dock icon.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { settings.show() }
        return true
    }
}
