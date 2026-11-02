import AppKit
import SwiftUI

@MainActor
final class OnboardingWindowController {
    private let permissions: Permissions
    private let hotKey: HotKey
    private var window: NSWindow?

    init(permissions: Permissions, hotKey: HotKey) {
        self.permissions = permissions
        self.hotKey = hotKey
    }

    func show() {
        permissions.refresh()
        if window == nil {
            let view = OnboardingView(permissions: permissions, hotKey: hotKey) { [weak self] in self?.close() }
            let window = NSWindow(contentViewController: NSHostingController(rootView: view))
            window.title = "Welcome to Tack"
            window.styleMask = [.titled, .closable, .fullSizeContentView]
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isMovableByWindowBackground = true
            window.isReleasedWhenClosed = false
            window.center()
            NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.permissions.stopWatching()
                    self?.window = nil
                }
            }
            self.window = window
        }
        // An agent app isn't active by default, so its windows would open behind whatever the user is in.
        // activate() is only a request since macOS 14 and is often refused when it comes from the menu bar menu,
        // so also order the window to the front regardless.
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
        window?.orderFrontRegardless()
    }

    private func close() {
        window?.close()
        window = nil
    }
}
