import AppKit

/// The menu bar menu. Mirrors the notch panel (F6) and is the only manager on Macs or displays without a notch.
@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()
    private let pinWindowMenu = NSMenu()
    private let openSettings: () -> Void
    private let openOnboarding: () -> Void
    private let checkForUpdates: () -> Void
    private let togglePin: () -> Void
    private let permissions: Permissions
    private let pins: PinManager
    private let hotKey: HotKey
    private var candidates: [PinManager.Candidate] = []

    init(openSettings: @escaping () -> Void, openOnboarding: @escaping () -> Void,
         checkForUpdates: @escaping () -> Void, togglePin: @escaping () -> Void,
         permissions: Permissions, pins: PinManager, hotKey: HotKey) {
        self.openSettings = openSettings
        self.openOnboarding = openOnboarding
        self.checkForUpdates = checkForUpdates
        self.togglePin = togglePin
        self.permissions = permissions
        self.pins = pins
        self.hotKey = hotKey
        super.init()
        statusItem.button?.image = Glyph.menuBarImage()
        menu.delegate = self
        pinWindowMenu.delegate = self
        statusItem.menu = menu
    }

    // MARK: NSMenuDelegate

    func menuNeedsUpdate(_ menu: NSMenu) {
        if menu === pinWindowMenu {
            rebuildPinWindowMenu()
        } else {
            rebuildMainMenu()
        }
    }

    func menuWillOpen(_ menu: NSMenu) {
        guard menu === self.menu, permissions.allGranted else { return }
        // The window list needs an async call; refresh it now so "Pin a Window" is current when opened.
        Task {
            candidates = await pins.candidates()
            rebuildPinWindowMenu()
        }
    }

    private func rebuildMainMenu() {
        menu.removeAllItems()
        permissions.refresh()
        if !permissions.allGranted {
            menu.addItem(item("Finish Setting Up Tack…", #selector(showOnboarding)))
            menu.addItem(.separator())
        }

        if pins.pins.isEmpty {
            let none = NSMenuItem(title: "No Windows Pinned", action: nil, keyEquivalent: "")
            none.isEnabled = false
            menu.addItem(none)
        } else {
            let header = NSMenuItem(title: "Pinned – front to back", action: nil, keyEquivalent: "")
            header.isEnabled = false
            menu.addItem(header)
            for (index, pin) in pins.pins.enumerated() {
                menu.addItem(pinItem(pin, index: index))
            }
            if pins.showsManyPinsWarning {
                let warning = NSMenuItem(title: "Lots of pins can slow your Mac down.", action: nil, keyEquivalent: "")
                warning.image = NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: "Warning")
                warning.isEnabled = false
                menu.addItem(warning)
            }
        }
        menu.addItem(.separator())

        let pinWindow = NSMenuItem(title: "Pin a Window", action: nil, keyEquivalent: "")
        pinWindow.submenu = pinWindowMenu
        pinWindow.isEnabled = permissions.allGranted
        menu.addItem(pinWindow)
        menu.addItem(pinFrontItem())
        if !pins.pins.isEmpty {
            menu.addItem(item("Unpin All", #selector(unpinAll)))
        }
        menu.addItem(.separator())
        menu.addItem(item("Settings…", #selector(showSettings), key: ","))
        menu.addItem(item("Check for Updates…", #selector(checkUpdates)))
        menu.addItem(item("Quit Tack", #selector(quit), key: "q"))
    }

    /// One row per pin, with the same actions as the notch panel row.
    private func pinItem(_ pin: Pin, index: Int) -> NSMenuItem {
        let title = pin.title == pin.appName ? pin.appName : "\(pin.appName) – \(pin.title)"
        let row = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        row.image = Self.icon(pin.appIcon)
        if pin.isMinimized { row.title += " (minimised)" }

        let submenu = NSMenu()
        submenu.addItem(item("Jump to Window", #selector(jump(_:)), pin: pin))

        submenu.addItem(.separator())
        let forward = item("Move Forward", #selector(moveForward(_:)), pin: pin)
        forward.isEnabled = index > 0
        submenu.addItem(forward)
        let back = item("Move Back", #selector(moveBack(_:)), pin: pin)
        back.isEnabled = index < pins.pins.count - 1
        submenu.addItem(back)
        submenu.addItem(.separator())
        submenu.addItem(item("Unpin", #selector(unpin(_:)), pin: pin))
        submenu.autoenablesItems = false
        row.submenu = submenu
        return row
    }

    /// Shows the current pin shortcut beside the item. Menus can only display a single character key this way,
    /// so other keys (Space, F5…) go in the title instead.
    private func pinFrontItem() -> NSMenuItem {
        let shortcut = hotKey.shortcut
        let symbols = "⌃⌥⇧⌘"
        let key = String(shortcut.display.drop { symbols.contains($0) })
        guard key.count == 1, key.unicodeScalars.allSatisfy({ $0.isASCII }) else {
            return item("Pin Front Window (\(shortcut.display))", #selector(pinFrontWindow))
        }
        let pinFront = item("Pin Front Window", #selector(pinFrontWindow), key: key.lowercased())
        var mask: NSEvent.ModifierFlags = []
        if shortcut.display.contains("⌃") { mask.insert(.control) }
        if shortcut.display.contains("⌥") { mask.insert(.option) }
        if shortcut.display.contains("⇧") { mask.insert(.shift) }
        if shortcut.display.contains("⌘") { mask.insert(.command) }
        pinFront.keyEquivalentModifierMask = mask
        return pinFront
    }

    private func rebuildPinWindowMenu() {
        pinWindowMenu.removeAllItems()
        if candidates.isEmpty {
            let none = NSMenuItem(title: "No Other Windows", action: nil, keyEquivalent: "")
            none.isEnabled = false
            pinWindowMenu.addItem(none)
            return
        }
        for candidate in candidates {
            let title = candidate.title == candidate.appName ? candidate.appName : "\(candidate.appName) – \(candidate.title)"
            let row = NSMenuItem(title: title, action: #selector(pinCandidate(_:)), keyEquivalent: "")
            row.target = self
            row.representedObject = candidate.id
            row.image = Self.icon(candidate.icon)
            pinWindowMenu.addItem(row)
        }
    }

    // MARK: Helpers

    private func item(_ title: String, _ action: Selector, key: String = "", pin: Pin? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        item.representedObject = pin
        return item
    }

    private static func icon(_ image: NSImage?) -> NSImage? {
        guard let copy = image?.copy() as? NSImage else { return nil }
        copy.size = NSSize(width: 16, height: 16)
        return copy
    }

    // MARK: Actions

    @objc private func jump(_ sender: NSMenuItem) {
        guard let pin = sender.representedObject as? Pin else { return }
        pins.jump(to: pin)
    }

    @objc private func moveForward(_ sender: NSMenuItem) {
        guard let pin = sender.representedObject as? Pin else { return }
        pins.move(pin, forward: true)
    }

    @objc private func moveBack(_ sender: NSMenuItem) {
        guard let pin = sender.representedObject as? Pin else { return }
        pins.move(pin, forward: false)
    }

    @objc private func unpin(_ sender: NSMenuItem) {
        guard let pin = sender.representedObject as? Pin else { return }
        pins.unpin(pin)
    }

    @objc private func pinCandidate(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? CGWindowID,
              let candidate = candidates.first(where: { $0.id == id }) else { return }
        pins.pin(candidate)
    }

    @objc private func showSettings() { openSettings() }
    @objc private func checkUpdates() { checkForUpdates() }
    @objc private func pinFrontWindow() { togglePin() }
    @objc private func unpinAll() { pins.unpinAll() }
    @objc private func showOnboarding() { openOnboarding() }
    @objc private func quit() { NSApp.terminate(nil) }
}
