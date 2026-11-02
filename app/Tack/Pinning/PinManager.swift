import AppKit
import ScreenCaptureKit

/// All pins, in stacking order (front first), and the rules between them: the pin in use is on top, and the
/// last-used pin tops the stack.
@MainActor
final class PinManager {
    /// Front-to-back.
    private(set) var pins: [Pin] = [] {
        didSet { changed() }
    }
    /// Called after anything the notch or menu shows changes.
    var onChange: (() -> Void)?

    private weak var activePin: Pin?
    private var settingsObserver: NSObjectProtocol?

    init() {
        settingsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                for pin in self?.pins ?? [] { pin.applySettings() }
            }
        }
    }

    // MARK: Lots of pins warning

    /// From this many pins, Tack suggests unpinning some. A plain count (Kelvin, 26 Oct): a size-based rule
    /// flickered as videos started and paused.
    static let warningPinCount = 4

    var showsManyPinsWarning: Bool { pins.count >= Self.warningPinCount }

    /// A window that could be pinned from a list (F2).
    struct Candidate: Identifiable {
        let id: CGWindowID
        let pid: pid_t
        let appName: String
        let title: String
        let icon: NSImage?
    }

    // MARK: Pinning

    /// Hotkey and menu action: pins the window the user is in, or unpins it if it's already pinned (F1, F4).
    func toggleFrontmost() {
        guard let front = NSWorkspace.shared.frontmostApplication,
              front.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
        guard let ax = AXWindow.frontmost() else {
            tackLog("pin: no focused window in frontmost app")
            NSSound.beep()
            return
        }
        if let existing = pins.first(where: { $0.windowID == ax.windowID }) {
            existing.close()
            return
        }
        Task { await pin(ax, inUse: true) }
    }

    /// Windows on screen that aren't pinned yet, for "Pin a Window" (F2).
    func candidates() async -> [Candidate] {
        guard let content = try? await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true) else { return [] }
        let myPID = ProcessInfo.processInfo.processIdentifier
        let pinned = Set(pins.map(\.windowID))
        return content.windows
            .filter { w in
                guard let app = w.owningApplication else { return false }
                return w.windowLayer == 0 && w.isOnScreen && app.processID != myPID && !pinned.contains(w.windowID)
                    && w.frame.width >= 80 && w.frame.height >= 80
            }
            .map { w in
                let app = w.owningApplication!
                let title = w.title.flatMap { $0.isEmpty ? nil : $0 } ?? app.applicationName
                return Candidate(id: w.windowID, pid: app.processID, appName: app.applicationName, title: title,
                                 icon: NSRunningApplication(processIdentifier: app.processID)?.icon)
            }
            .sorted { ($0.appName, $0.title) < ($1.appName, $1.title) }
    }

    func pin(_ candidate: Candidate) {
        guard let ax = AXWindow.find(windowID: candidate.id, pid: candidate.pid) else {
            tackLog("pin: window \(candidate.id) not found via Accessibility")
            NSSound.beep()
            return
        }
        Task { await pin(ax, inUse: false) }
    }

    func unpin(_ pin: Pin) {
        pin.close()
    }

    func unpinAll() {
        for pin in pins { pin.close() }
    }

    private func pin(_ ax: AXWindow, inUse: Bool) async {
        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
        } catch {
            tackLog("pin: can't list windows: \(error.localizedDescription)")
            NSSound.beep()
            return
        }
        guard let window = content.windows.first(where: { $0.windowID == ax.windowID }),
              !pins.contains(where: { $0.windowID == ax.windowID }) else {
            tackLog("pin: window \(ax.windowID) not capturable")
            NSSound.beep()
            return
        }
        let pin = Pin(window: window, ax: ax)
        pin.onClose = { [weak self] closed in self?.removed(closed) }
        pin.onSwappedIn = { [weak self] pin in self?.activated(pin) }
        pin.onSwappedOut = { [weak self] pin in self?.deactivated(pin) }
        pins.insert(pin, at: 0)
        pin.start(inUse: inUse)
    }

    private func removed(_ pin: Pin) {
        pins.removeAll { $0 === pin }
    }

    // MARK: Row actions

    func jump(to pin: Pin) {
        pin.jumpTo()
    }

    /// Moves a pin one layer forward (towards the front) or back.
    func move(_ pin: Pin, forward: Bool) {
        guard let index = pins.firstIndex(where: { $0 === pin }) else { return }
        let target = forward ? index - 1 : index + 1
        guard pins.indices.contains(target) else { return }
        pins.swapAt(index, target)
        applyStackOrder()
    }

    /// Drag-to-reorder from the notch list (front-to-back indices).
    func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        pins.move(fromOffsets: source, toOffset: destination)
        applyStackOrder()
    }

    /// Re-layers the floating pins to match `pins`. Pins stepped down below an active real window are left
    /// alone; they're re-layered when that window is done.
    private func applyStackOrder() {
        for pin in pins.reversed() where !pin.isLowered {
            pin.bringToFront()
        }
    }

    // MARK: Pin stack

    /// The pin in use tops the stack: every other pin steps down below its real window.
    private func activated(_ pin: Pin) {
        activePin = pin
        for other in pins where other !== pin {
            other.setLowered(true, below: pin.windowID)
        }
        changed()
    }

    /// Only the active pin can end the session; a pin swapped out because another took over is ignored.
    /// The last-used pin moves to the front of the stack.
    private func deactivated(_ pin: Pin) {
        guard activePin === pin else { return }
        activePin = nil
        for other in pins where other !== pin {
            other.setLowered(false)
        }
        if let index = pins.firstIndex(where: { $0 === pin }), index != 0 {
            pins.remove(at: index)
            pins.insert(pin, at: 0)
        }
        applyStackOrder()
    }

    private func changed() {
        onChange?()
    }
}
