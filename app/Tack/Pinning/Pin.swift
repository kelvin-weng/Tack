import AppKit
import ScreenCaptureKit

/// One pinned window: a floating panel showing a live mirror, with the real window kept exactly underneath.
///
/// Swap in place (REQUIREMENTS section 2): pressing the pin brings the real window forward and hands it the
/// press, so the real app gets the whole gesture. Clicking anywhere else, or activating another app or window,
/// shows the mirror again.
@MainActor
final class Pin {
    let windowID: CGWindowID
    let appName: String
    let title: String
    let appIcon: NSImage?

    var onClose: ((Pin) -> Void)?
    var onSwappedIn: ((Pin) -> Void)?
    var onSwappedOut: ((Pin) -> Void)?

    private let ax: AXWindow
    private let panel: PinPanel
    private var view: PinView!
    private var capture: WindowCapture!

    private(set) var swappedIn = false
    private var closed = false
    private var dragging = false
    private var dragOffset = CGVector.zero
    private var pressWasDrag = false
    private var captureNeedsRestart = false
    private var workspaceObserver: NSObjectProtocol?
    private var clickMonitor: Any?
    private var releaseMonitor: Any?
    /// The real window's frame when the current press started, to tell a move from a click or resize.
    private var frameAtPress: CGRect?
    private var snapTimer: Timer?

    init(window: SCWindow, ax: AXWindow) {
        windowID = window.windowID
        appName = window.owningApplication?.applicationName ?? "?"
        title = window.title.flatMap { $0.isEmpty ? nil : $0 } ?? appName
        appIcon = window.owningApplication.flatMap { NSRunningApplication(processIdentifier: $0.processID)?.icon }
        self.ax = ax

        let frame = Geometry.cocoa(fromCG: ax.frame ?? window.frame)
        panel = PinPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel],
                         backing: .buffered, defer: false)
        view = PinView(frame: NSRect(origin: .zero, size: frame.size),
                       onUnpin: { [weak self] in self?.close() },
                       onBringBack: { [weak self] in self?.bringBack() })
        capture = WindowCapture(window: window, layer: view.imageLayer)

        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false // Tack is an agent app, so it's almost never "active"
        panel.isReleasedWhenClosed = false
        panel.contentView = view
        view.setAccessibilityElement(true)
        view.setAccessibilityRole(.group)
        view.setAccessibilityLabel("Pinned copy of \(title == appName ? appName : "\(appName), \(title)")")
        view.setAccessibilityHelp("Press to use the real window.")

        view.onPress = { [weak self] point, inDragStrip in self?.swapIn(pressAt: point, fromDragStrip: inDragStrip) }
        view.onDragBegan = { [weak self] start in self?.dragBegan(at: start) }
        view.onDrag = { [weak self] mouse in self?.drag(to: mouse) }
        view.onDragEnded = { [weak self] in self?.dragEnded() }
    }

    /// Pinned from the hotkey, the user is in the window, so it starts swapped in: the real window stays active and
    /// the mirror appears as soon as they click elsewhere. Pinned from a list, the mirror shows straight away.
    func start(inUse: Bool) {
        capture.onStopped = { [weak self] _ in self?.captureStopped() }
        capture.onCorners = { [weak self] corners in
            guard let self else { return }
            view.useCorners(corners)
            tackLog("pin: corner radius \(Int(corners.radius.rounded())) pt measured for \(appName)")
        }
        applySettings()
        capture.start()

        ax.onEvent = { [weak self] event in self?.handle(event) }
        ax.startObserving()
        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let pid = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.processIdentifier
            MainActor.assumeIsolated { self?.appActivated(pid: pid) }
        }

        panel.orderFrontRegardless()
        if inUse {
            setMirrorVisible(false)
            swappedIn = true
            capture.rate = .background
            startWatchingClicksElsewhere()
            onSwappedIn?(self)
        }
        tackLog("pin: started (window \(windowID), in use \(inUse))")
    }

    func close() {
        guard !closed else { return }
        closed = true
        if swappedIn { onSwappedOut?(self) }
        if let workspaceObserver { NSWorkspace.shared.notificationCenter.removeObserver(workspaceObserver) }
        snapTimer?.invalidate()
        stopWatchingClicksElsewhere()
        ax.stopObserving()
        capture.stop()
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.15
            panel.animator().alphaValue = 0
        }, completionHandler: { [panel] in
            MainActor.assumeIsolated { panel.orderOut(nil) }
        })
        tackLog("pin: closed (window \(windowID))")
        onClose?(self)
    }

    // MARK: Stacking (managed by PinManager)

    /// While another pin's real window is in use, this pin drops to normal level just below that window,
    /// so it can't cover it or catch the press being handed to it.
    private(set) var isLowered = false

    func setLowered(_ lowered: Bool, below windowID: CGWindowID? = nil) {
        isLowered = lowered
        panel.level = lowered ? .normal : .floating
        if lowered, let windowID { panel.order(.below, relativeTo: Int(windowID)) }
    }

    func bringToFront() {
        panel.orderFrontRegardless()
    }

    // MARK: Settings › Pins

    func applySettings() {
        view.showsBorder = PinSettings.showBorder
        view.borderColor = PinSettings.borderColor
    }

    // MARK: Actions from the notch and menu bar

    var isMinimized: Bool { view.isUnavailable }

    /// "Jump to window": brings the real window forward in place, as if the pin had been clicked.
    func jumpTo() {
        if view.isUnavailable {
            bringBack()
        } else {
            swapIn(pressAt: nil)
        }
    }

    // MARK: Swap in place

    /// `point` is where the user pressed on the pin (CG); nil just brings the real window forward.
    private func swapIn(pressAt point: CGPoint?, fromDragStrip: Bool = false) {
        guard !swappedIn, !view.isUnavailable else { return }
        swappedIn = true
        pressWasDrag = false
        frameAtPress = ax.frame
        onSwappedIn?(self)
        capture.rate = .background
        let started = CACurrentMediaTime()
        let panelFrame = Geometry.cg(fromCocoa: panel.frame)
        let center = CGPoint(x: panelFrame.midX, y: panelFrame.midY)
        ax.raise()

        // Hide the mirror only once the real window is in front, so nothing behind it flashes through. Wait until
        // it's also focused and topmost under the cursor: earlier, apps like Chrome treat the press as an
        // "activation click" and ignore it.
        waitUntil({ [ax, windowID] in
            guard NSWorkspace.shared.frontmostApplication?.processIdentifier == ax.pid else { return false }
            let probe = point == nil ? center : Geometry.mouseLocationCG
            return ax.isFocusedWindow && Self.topmostWindow(at: probe) == windowID
        }, timeout: 0.6) { [weak self] ready in
            guard let self, !self.closed else { return }
            self.setMirrorVisible(false)
            self.startWatchingClicksElsewhere()
            // One more frame so the window server has applied the new ordering before the press lands.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.016) { [weak self] in
                MainActor.assumeIsolated {
                    guard let self, let point else { return }
                    let action = self.handOff(pressAt: point, fromDragStrip: fromDragStrip)
                    tackLog("pin: swap in, \(action) after \(Int((CACurrentMediaTime() - started) * 1000)) ms (ready \(ready))")
                }
            }
        }
    }

    /// If the button is still down, replay only the mouse-down so the real app owns the rest of the gesture
    /// (a window drag, resize, text selection, scrubbing). If the user already let go, replay a click.
    private func handOff(pressAt point: CGPoint, fromDragStrip: Bool) -> String {
        let held = NSEvent.pressedMouseButtons & 1 != 0
        if held {
            dragging = false
            view.cancelTracking()
            let now = Geometry.mouseLocationCG
            if fromDragStrip {
                // The pin and real window moved with the cursor, so the title bar is under the cursor now.
                Self.post(.leftMouseDown, at: now)
            } else {
                // Start where the user pressed (e.g. on a resize edge), then catch up with the cursor.
                Self.post(.leftMouseDown, at: point)
                if hypot(now.x - point.x, now.y - point.y) > 1 { Self.post(.leftMouseDragged, at: now) }
            }
            return "handed press"
        }
        if pressWasDrag { return "drag already ended" }
        Self.post(.leftMouseDown, at: point)
        Self.post(.leftMouseUp, at: point)
        return "replayed click"
    }

    private func swapOut() {
        guard swappedIn, !closed else { return }
        swappedIn = false
        stopWatchingClicksElsewhere()
        onSwappedOut?(self)
        capture.rate = .live
        if let frame = ax.frame { followRealWindow(to: frame) }
        setMirrorVisible(true)
    }

    private func appActivated(pid: pid_t?) {
        guard swappedIn, pid != ax.pid else { return }
        swapOut()
    }

    /// Hiding via alpha keeps the panel in the window list, so showing it again is a one-frame change rather than
    /// a reorder (which flashed).
    private func setMirrorVisible(_ visible: Bool) {
        panel.alphaValue = visible ? 1 : 0
        panel.ignoresMouseEvents = !visible
        if !visible { view.setToolbarVisible(false) }
    }

    /// Shows the mirror the moment the user clicks outside the real window, instead of waiting for the other
    /// app's activation (by then it has already drawn over the pin's spot).
    private func startWatchingClicksElsewhere() {
        guard clickMonitor == nil else { return }
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            MainActor.assumeIsolated {
                guard let self else { return }
                guard !self.panel.frame.contains(NSEvent.mouseLocation) else {
                    if event.type == .leftMouseDown { self.frameAtPress = self.ax.frame }
                    return
                }
                self.swapOut()
            }
        }
        releaseMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { [weak self] _ in
            MainActor.assumeIsolated { self?.pressEnded() }
        }
    }

    private func stopWatchingClicksElsewhere() {
        if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
        if let releaseMonitor { NSEvent.removeMonitor(releaseMonitor) }
        clickMonitor = nil
        releaseMonitor = nil
    }

    // MARK: Snapping (F12)

    /// When a drag of the real window ends near a screen edge or corner, slide it the rest of the way.
    /// The real app owns the drag itself, so snapping happens on release rather than during the move.
    private func pressEnded() {
        guard let before = frameAtPress else { return }
        frameAtPress = nil
        guard let after = ax.frame,
              Geometry.roughlyEqual(CGRect(origin: .zero, size: before.size), CGRect(origin: .zero, size: after.size)),
              hypot(after.minX - before.minX, after.minY - before.minY) > 2,
              let target = Self.snapped(after) else { return }
        slide(from: after.origin, to: target.origin)
    }

    private static let snapDistance: CGFloat = 24
    private static let snapMargin: CGFloat = 10

    /// The frame moved onto the nearest edges of its screen's usable area, or nil if no edge is close (CG coords).
    private static func snapped(_ frame: CGRect) -> CGRect? {
        let cocoa = Geometry.cocoa(fromCG: frame)
        guard let screen = NSScreen.screens.max(by: { overlap($0.frame, cocoa) < overlap($1.frame, cocoa) }),
              overlap(screen.frame, cocoa) > 0 else { return nil }
        let area = screen.visibleFrame.insetBy(dx: snapMargin, dy: snapMargin)
        var origin = cocoa.origin
        if abs(cocoa.minX - area.minX) < snapDistance { origin.x = area.minX }
        else if abs(cocoa.maxX - area.maxX) < snapDistance { origin.x = area.maxX - cocoa.width }
        if abs(cocoa.minY - area.minY) < snapDistance { origin.y = area.minY }
        else if abs(cocoa.maxY - area.maxY) < snapDistance { origin.y = area.maxY - cocoa.height }
        guard origin != cocoa.origin else { return nil }
        return Geometry.cg(fromCocoa: NSRect(origin: origin, size: cocoa.size))
    }

    private static func overlap(_ a: CGRect, _ b: CGRect) -> CGFloat {
        let i = a.intersection(b)
        return i.isNull ? 0 : i.width * i.height
    }

    /// A short ease-out slide; the pin follows through the usual move notifications.
    private func slide(from start: CGPoint, to end: CGPoint) {
        snapTimer?.invalidate()
        let began = CACurrentMediaTime()
        let duration = Motion.reduced ? 0.0 : 0.15
        snapTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                guard !self.closed else { self.snapTimer?.invalidate(); return }
                let t = duration > 0 ? min((CACurrentMediaTime() - began) / duration, 1) : 1
                let eased = 1 - pow(1 - t, 3)
                self.ax.setPosition(CGPoint(x: start.x + (end.x - start.x) * eased, y: start.y + (end.y - start.y) * eased))
                if t >= 1 {
                    self.snapTimer?.invalidate()
                    self.snapTimer = nil
                    if let frame = self.ax.frame { self.followRealWindow(to: frame) }
                }
            }
        }
    }

    // MARK: Moving the pin from its top edge

    private func dragBegan(at mouse: NSPoint) {
        dragging = true
        pressWasDrag = true
        dragOffset = CGVector(dx: mouse.x - panel.frame.minX, dy: mouse.y - panel.frame.minY)
    }

    /// Only runs for the ~50 ms until the press is handed to the real window, which then drags natively.
    /// Positions from a fixed offset to the cursor so fast moves can't accumulate drift.
    private func drag(to mouse: NSPoint) {
        let origin = NSPoint(x: mouse.x - dragOffset.dx, y: mouse.y - dragOffset.dy)
        panel.setFrameOrigin(origin)
        ax.setPosition(Geometry.cg(fromCocoa: NSRect(origin: origin, size: panel.frame.size)).origin)
    }

    private func dragEnded() {
        dragging = false
        guard let frame = ax.frame else { return }
        followRealWindow(to: frame)
        if let target = Self.snapped(frame) { slide(from: frame.origin, to: target.origin) }
    }

    // MARK: Following the real window

    private func handle(_ event: AXWindow.Event) {
        switch event {
        case .movedOrResized:
            guard !dragging, let frame = ax.frame else { return }
            followRealWindow(to: frame)
        case .focusedWindowChanged:
            // The same app switching to another of its windows (e.g. Chrome's main window) hands back to the pin.
            if swappedIn, !ax.isFocusedWindow { swapOut() }
        case .minimized:
            showUnavailable(true)
        case .deminimized:
            showUnavailable(false)
        case .destroyed:
            close()
        }
    }

    /// Resizing happens on the real window (a press on the pin's edge is handed over as a resize), so the
    /// pin only ever follows; it never pushes its frame back onto the real window.
    private func followRealWindow(to frame: CGRect) {
        let target = Geometry.cocoa(fromCG: frame)
        guard !Geometry.roughlyEqual(panel.frame, target) else { return }
        panel.setFrame(target, display: true)
        capture.resize(to: frame.size)
    }

    // MARK: Source window unavailable (F9)

    private func showUnavailable(_ unavailable: Bool) {
        guard view.isUnavailable != unavailable else { return }
        tackLog("pin: source \(unavailable ? "minimised" : "restored") (window \(windowID))")
        if unavailable, swappedIn {
            swappedIn = false
            stopWatchingClicksElsewhere()
            onSwappedOut?(self)
        }
        view.isUnavailable = unavailable
        setMirrorVisible(unavailable || !swappedIn)
        if !unavailable, captureNeedsRestart {
            captureNeedsRestart = false
            capture.start()
        }
        if !unavailable, swappedIn == false, ax.isFocusedWindow { swapIn(pressAt: nil) }
    }

    private func bringBack() {
        ax.deminimize()
    }

    private func captureStopped() {
        // A minimised window can stop its capture; the pin stays (showing "minimised") and capture restarts on
        // restore. Anything else means the window is gone.
        if ax.isMinimized {
            captureNeedsRestart = true
            showUnavailable(true)
            return
        }
        close()
    }

    // MARK: Helpers

    private static func post(_ type: CGEventType, at point: CGPoint) {
        let source = CGEventSource(stateID: .hidSystemState)
        CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: point, mouseButton: .left)?
            .post(tap: .cghidEventTap)
    }

    /// Front-most normal-level window containing the point, ignoring Tack's own panels.
    private static func topmostWindow(at point: CGPoint) -> CGWindowID? {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]] else { return nil }
        let myPID = ProcessInfo.processInfo.processIdentifier
        for info in list {
            guard (info[kCGWindowLayer as String] as? Int) == 0,
                  (info[kCGWindowOwnerPID as String] as? pid_t) != myPID,
                  let boundsDict = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDict),
                  bounds.contains(point) else { continue }
            return info[kCGWindowNumber as String] as? CGWindowID
        }
        return nil
    }

    private func waitUntil(_ condition: @escaping () -> Bool, timeout: TimeInterval, then done: @escaping (Bool) -> Void) {
        let deadline = CACurrentMediaTime() + timeout
        func check() {
            if condition() { done(true); return }
            if CACurrentMediaTime() > deadline { done(false); return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.005) { MainActor.assumeIsolated { check() } }
        }
        check()
    }
}
