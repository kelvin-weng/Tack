import AppKit
import ScreenCaptureKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private let menu = NSMenu()
    private var windows: [SCWindow] = []
    private var mirrors: [Mirror] = [] {
        didSet { notch?.update(pins: mirrors) }
    }
    private var notch: NotchController?
    private var lastError: String?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "pin.fill", accessibilityDescription: "Tack Spike")
        menu.delegate = self
        statusItem.menu = menu
        notch = NotchController()

        if !CGPreflightScreenCaptureAccess() {
            spikeLog("Screen Recording not granted, requesting")
            CGRequestScreenCaptureAccess()
        }
        if !AXWindow.isTrusted {
            spikeLog("Accessibility not granted, requesting")
            AXWindow.requestTrust()
        }
        Task { await refreshWindows() }
    }

    // MARK: Menu

    func menuWillOpen(_ menu: NSMenu) {
        rebuildMenu()
        // The window list can be stale; refresh and update the open menu in place.
        Task {
            await refreshWindows()
            rebuildMenu()
        }
    }

    private func rebuildMenu() {
        menu.removeAllItems()

        if let lastError {
            let item = NSMenuItem(title: "Can't list windows: \(lastError)", action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
            menu.addItem(NSMenuItem(title: "Open Screen Recording Settings…", action: #selector(openScreenRecordingSettings), keyEquivalent: ""))
        } else {
            let header = NSMenuItem(title: "Mirror a window", action: nil, keyEquivalent: "")
            header.isEnabled = false
            menu.addItem(header)
            for window in windows {
                let app = window.owningApplication?.applicationName ?? "?"
                let title = window.title.flatMap { $0.isEmpty ? nil : $0 } ?? "Untitled"
                let item = NSMenuItem(title: "\(app) – \(title)", action: #selector(mirrorWindow(_:)), keyEquivalent: "")
                item.representedObject = window.windowID
                if let pid = window.owningApplication?.processID,
                   let icon = NSRunningApplication(processIdentifier: pid)?.icon {
                    icon.size = NSSize(width: 16, height: 16)
                    item.image = icon
                }
                menu.addItem(item)
            }
        }

        if !AXWindow.isTrusted {
            menu.addItem(.separator())
            let warning = NSMenuItem(title: "Accessibility is off – click-to-swap won't work", action: nil, keyEquivalent: "")
            warning.isEnabled = false
            menu.addItem(warning)
            menu.addItem(NSMenuItem(title: "Open Accessibility Settings…", action: #selector(openAccessibilitySettings), keyEquivalent: ""))
        }

        menu.addItem(.separator())
        let fps = NSMenuItem(title: "Capture at 120 fps", action: #selector(toggleFrameRate), keyEquivalent: "")
        fps.state = Mirror.maxFrameRate == 120 ? .on : .off
        menu.addItem(fps)
        let yuv = NSMenuItem(title: "Capture in YUV", action: #selector(toggleYUV), keyEquivalent: "")
        yuv.state = Mirror.useYUV ? .on : .off
        menu.addItem(yuv)
        let show = NSMenuItem(title: "Show captured frames", action: #selector(toggleShowFrames), keyEquivalent: "")
        show.state = Mirror.showFrames ? .on : .off
        menu.addItem(show)
        let close = NSMenuItem(title: "Close All Mirrors (\(mirrors.count))", action: #selector(closeAllMirrors), keyEquivalent: "")
        close.isEnabled = !mirrors.isEmpty
        menu.addItem(close)
        menu.addItem(NSMenuItem(title: "Quit Tack Spike", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        for item in menu.items where item.action != #selector(NSApplication.terminate(_:)) {
            item.target = self
        }
    }

    private func refreshWindows() async {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
            let myPID = ProcessInfo.processInfo.processIdentifier
            windows = content.windows
                .filter { w in
                    guard let app = w.owningApplication else { return false }
                    return w.windowLayer == 0 && w.isOnScreen && app.processID != myPID
                        && w.frame.width >= 80 && w.frame.height >= 80
                }
                .sorted { ($0.owningApplication?.applicationName ?? "") < ($1.owningApplication?.applicationName ?? "") }
            lastError = nil
        } catch {
            spikeLog("SCShareableContent failed: \(error)")
            lastError = error.localizedDescription
        }
    }

    // MARK: Actions

    @objc private func mirrorWindow(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? CGWindowID,
              let window = windows.first(where: { $0.windowID == id }) else { return }
        let mirror = Mirror(window: window)
        mirror.onClose = { [weak self] closed in
            self?.mirrors.removeAll { $0 === closed }
        }
        mirror.onSwappedIn = { [weak self] pin in self?.pinActivated(pin) }
        mirror.onSwappedOut = { [weak self] pin in self?.pinDeactivated(pin) }
        mirrors.append(mirror)
        mirror.start()
    }

    // MARK: Pin stack

    private weak var activePin: Mirror?

    /// The pin in use tops the stack: every other pin steps down below its real window.
    private func pinActivated(_ pin: Mirror) {
        activePin = pin
        for other in mirrors where other !== pin {
            other.setLowered(true, below: pin.windowID)
        }
    }

    /// Only the currently active pin can end the session; a pin swapped out because another took over is ignored.
    private func pinDeactivated(_ pin: Mirror) {
        guard activePin === pin else { return }
        activePin = nil
        for other in mirrors where other !== pin {
            other.setLowered(false)
        }
        pin.bringToFront() // last used pin is on top
    }

    @objc private func toggleFrameRate() {
        Mirror.maxFrameRate = Mirror.maxFrameRate == 120 ? 60 : 120
        spikeLog("capture frame rate cap: \(Mirror.maxFrameRate) fps")
        for mirror in mirrors { mirror.applyFrameRate() }
    }

    @objc private func toggleYUV() {
        Mirror.useYUV.toggle()
        spikeLog("capture format: \(Mirror.useYUV ? "YUV 420v" : "BGRA")")
        for mirror in mirrors { mirror.applyFrameRate() }
    }

    @objc private func toggleShowFrames() {
        Mirror.showFrames.toggle()
        spikeLog("show captured frames: \(Mirror.showFrames)")
        for mirror in mirrors { mirror.applyShowFrames() }
    }

    @objc private func closeAllMirrors() {
        for mirror in mirrors { mirror.close() }
    }

    @objc private func openAccessibilitySettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    @objc private func openScreenRecordingSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
    }
}
