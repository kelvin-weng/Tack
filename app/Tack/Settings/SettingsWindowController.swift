import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController {
    private var window: NSWindow?
    private let launchAtLogin = LaunchAtLogin()
    private let hotKey: HotKey

    init(hotKey: HotKey) {
        self.hotKey = hotKey
    }

    func show() {
        if window == nil {
            let tabs = NSTabViewController()
            tabs.tabStyle = .toolbar
            tabs.addTabViewItem(tab("General", symbol: "gearshape", GeneralSettingsView(launchAtLogin: launchAtLogin, hotKey: hotKey)))
            tabs.addTabViewItem(tab("Pins", symbol: "pin", PinsSettingsView()))
            tabs.addTabViewItem(tab("Guide", symbol: "questionmark.circle", HowTackWorksView(hotKey: hotKey)))
            tabs.addTabViewItem(tab("About", symbol: "info.circle", AboutView()))

            let window = NSWindow(contentViewController: tabs)
            window.styleMask = [.titled, .closable]
            window.toolbarStyle = .preference
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        launchAtLogin.refresh()
        // An agent app isn't active by default, so its windows would open behind whatever the user is in.
        // activate() is only a request since macOS 14 and is often refused when it comes from the menu bar menu,
        // so also order the window to the front regardless.
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
        window?.orderFrontRegardless()
    }

    private func tab(_ label: String, symbol: String, _ view: some View) -> NSTabViewItem {
        let controller = NSHostingController(rootView: view.frame(width: 480))
        // Let each tab size the window to its content.
        controller.sizingOptions = .preferredContentSize
        // The tab view controller shows the selected tab's title as the window title ("Untitled" without one).
        controller.title = label
        let item = NSTabViewItem(viewController: controller)
        item.label = label
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
        return item
    }
}
