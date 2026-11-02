import AppKit
import ScreenCaptureKit
import Synchronization

/// One pin: a floating panel showing a live ScreenCaptureKit stream of a window, with the real window
/// kept underneath it. Clicking the pin swaps the real window in; activating anything else swaps the mirror back.
@MainActor
final class Mirror: NSObject {
    var onClose: ((Mirror) -> Void)?
    /// Swap-in/out notifications, so the app can keep the active pin on top of the pin stack.
    var onSwappedIn: ((Mirror) -> Void)?
    var onSwappedOut: ((Mirror) -> Void)?

    var windowID: CGWindowID { window.windowID }

    var appName: String { window.owningApplication?.applicationName ?? "?" }
    var title: String { window.title.flatMap { $0.isEmpty ? nil : $0 } ?? "Untitled" }
    var appIcon: NSImage? {
        window.owningApplication.flatMap { NSRunningApplication(processIdentifier: $0.processID)?.icon }
    }

    private let window: SCWindow
    private let ax: AXWindow?
    private let panel: NSPanel
    private let view: MirrorView
    private let output = FrameOutput()
    private var stream: SCStream?
    private var captureScale: CGFloat = 2
    private var fpsTimer: Timer?
    private var workspaceObserver: NSObjectProtocol?
    private var swappedIn = false
    private var closed = false

    init(window: SCWindow) {
        self.window = window
        let pid = window.owningApplication?.processID ?? 0
        ax = AXWindow.find(windowID: window.windowID, pid: pid)
        if ax == nil { spikeLog("no AX window for \(window.windowID); swap disabled") }

        let frame = Geometry.cocoa(fromCG: window.frame)
        panel = PinPanel(contentRect: frame,
                        styleMask: [.borderless, .nonactivatingPanel, .resizable],
                        backing: .buffered, defer: false)
        view = MirrorView(frame: NSRect(origin: .zero, size: frame.size))
        super.init()

        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false // we're an accessory app, so we're almost never "active"
        // Excluded from capture: without this, every frame drawn on the pin made macOS re-capture the window
        // underneath, a feedback loop that sent full frames of static windows at the display's refresh rate.
        panel.sharingType = .none
        panel.isReleasedWhenClosed = false
        panel.contentAspectRatio = frame.size
        panel.contentView = view

        let menu = NSMenu()
        let close = NSMenuItem(title: "Close Mirror", action: #selector(closeFromMenu), keyEquivalent: "")
        close.target = self
        menu.addItem(close)
        view.menu = menu

        view.onPress = { [weak self] point in self?.swapIn(pressAt: point) }
        view.onDragBegan = { [weak self] start in self?.dragBegan(at: start) }
        view.onDrag = { [weak self] mouse in self?.drag(to: mouse) }
        view.onDragEnded = { [weak self] in self?.dragEnded() }

        NotificationCenter.default.addObserver(self, selector: #selector(panelMovedOrResized),
                                               name: NSWindow.didMoveNotification, object: panel)
        NotificationCenter.default.addObserver(self, selector: #selector(panelMovedOrResized),
                                               name: NSWindow.didResizeNotification, object: panel)
        NotificationCenter.default.addObserver(self, selector: #selector(panelEndedResize),
                                               name: NSWindow.didEndLiveResizeNotification, object: panel)
    }

    // MARK: Capture

    func start() {
        let filter = SCContentFilter(desktopIndependentWindow: window)
        captureScale = CGFloat(filter.pointPixelScale)

        output.layer = view.imageLayer
        output.onIdleChanged = { [weak self] idle in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self, self.idle != idle else { return }
                    self.idle = idle
                    self.applyFrameRate()
                }
            }
        }
        output.name = "\(appName) – \(title)"
        output.onStop = { [weak self] message in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    spikeLog("stream stopped: \(message)")
                    self?.close()
                }
            }
        }

        let stream = SCStream(filter: filter, configuration: makeConfig(size: filter.contentRect.size), delegate: output)
        do {
            try stream.addStreamOutput(output, type: .screen, sampleHandlerQueue: output.queue)
        } catch {
            spikeLog("addStreamOutput failed: \(error)")
            close()
            return
        }
        self.stream = stream
        stream.startCapture { [weak self] error in
            guard let error else { return }
            let message = error.localizedDescription
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    spikeLog("startCapture failed: \(message)")
                    self?.close()
                }
            }
        }

        if let ax {
            ax.onMovedOrResized = { [weak self] in self?.sourceMovedOrResized() }
            ax.onFocusedWindowChanged = { [weak self] in self?.sourceAppFocusChanged() }
            ax.onDestroyed = { [weak self] in self?.close() }
            ax.startObserving()
        }
        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let pid = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.processIdentifier
            MainActor.assumeIsolated { self?.appActivated(pid: pid) }
        }

        panel.orderFrontRegardless()
        fpsTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                // Only touch the label when the text changes: each redraw of the pin triggers a re-capture.
                let text = "\(self.output.takeFrameCount()) fps"
                if self.view.fpsLabel.stringValue != text { self.view.fpsLabel.stringValue = text }
            }
        }
    }

    private func makeConfig(size: CGSize) -> SCStreamConfiguration {
        let config = SCStreamConfiguration()
        config.width = Int(size.width * captureScale)
        config.height = Int(size.height * captureScale)
        // While swapped in the real window is what's on screen, so the mirror only needs a trickle of frames.
        let fps = swappedIn ? 1 : idle ? Mirror.idleFrameRate : Mirror.maxFrameRate
        config.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(fps))
        if Mirror.useYUV {
            // ~1.5 bytes per pixel instead of 4: far less memory traffic per frame.
            config.pixelFormat = kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
            config.colorMatrix = CGDisplayStream.yCbCrMatrix_ITU_R_709_2
        } else {
            config.pixelFormat = kCVPixelFormatType_32BGRA
        }
        config.showsCursor = false
        config.queueDepth = 3
        config.scalesToFit = true
        config.preservesAspectRatio = true
        config.captureResolution = .best
        return config
    }

    /// Spike-only toggle for measuring the cost of 120 fps capture in test 4.
    static var maxFrameRate = 60
    static let idleFrameRate = 10
    private var idle = false
    /// Spike-only toggle, in case YUV frames don't display correctly.
    static var useYUV = true
    /// Spike-only: keep capturing but stop putting frames on the pin, to test for a capture/display feedback loop.
    static var showFrames = true

    func applyShowFrames() {
        output.layer = Mirror.showFrames ? view.imageLayer : nil
    }

    func applyFrameRate() {
        updateCaptureSize(Geometry.cg(fromCocoa: panel.frame).size)
    }

    /// Keeps capture pixels 1:1 with the window so the mirror stays sharp after a resize.
    private func updateCaptureSize(_ size: CGSize) {
        stream?.updateConfiguration(makeConfig(size: size)) { error in
            if let error { spikeLog("updateConfiguration failed: \(error.localizedDescription)") }
        }
    }


    // MARK: Swap in place

    /// `point` is where the user pressed on the pin; nil just brings the real window forward (e.g. after a drag).
    /// The press is handed to the real window: if the button is still down by the time it's ready, only a
    /// mouse-down is replayed, so the rest of the gesture (a window drag, text selection, scrubbing) goes to
    /// the real app natively. If the user already let go, a whole click is replayed.
    private func swapIn(pressAt point: CGPoint?) {
        guard let ax, !swappedIn else { return }
        let center = CGPoint(x: Geometry.cg(fromCocoa: panel.frame).midX, y: Geometry.cg(fromCocoa: panel.frame).midY)
        swappedIn = true
        pressWasDrag = false
        onSwappedIn?(self)
        applyFrameRate()
        let started = CACurrentMediaTime()
        ax.raise()
        let windowID = window.windowID
        var frontmostAt: Double?
        // Hide the mirror only once the real window is in front, so nothing behind it flashes through.
        // Then wait until it's also the focused window and topmost under the cursor: replaying the click
        // earlier makes it an "activation click" that apps like Chrome swallow.
        waitUntil({
            guard NSWorkspace.shared.frontmostApplication?.processIdentifier == ax.pid else { return false }
            if frontmostAt == nil { frontmostAt = CACurrentMediaTime() }
            // Probe under the cursor: the pin may have been dragged since the press.
            let probe = point == nil ? center : Geometry.cg(fromCocoa: NSEvent.mouseLocation)
            return ax.isFocusedWindow && Self.topmostWindow(at: probe) == windowID
        }, timeout: 0.6) { [weak self] ok in
            guard let self, !self.closed else { return }
            self.setMirrorVisible(false)
            self.startWatchingClicksElsewhere()
            let ready = CACurrentMediaTime()
            let frontmost = frontmostAt
            // One more frame so the window server has applied the new ordering before the click lands.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.016) { [weak self] in
                MainActor.assumeIsolated {
                    guard let self, let point else { return }
                    let held = NSEvent.pressedMouseButtons & 1 != 0
                    let action: String
                    if held {
                        // From here the real app owns the gesture; the pin just follows the real window.
                        self.dragging = false
                        self.view.cancelTracking()
                        Self.post(.leftMouseDown, at: Geometry.cg(fromCocoa: NSEvent.mouseLocation))
                        action = "handed press"
                    } else if self.pressWasDrag {
                        action = "drag already ended, no click"
                    } else {
                        Self.postClick(at: point)
                        action = "replayed click"
                    }
                    let ms = { (t: Double?) in t.map { "\(Int(($0 - started) * 1000))" } ?? "-" }
                    spikeLog("swap in: frontmost \(ms(frontmost)) ms, ready \(ms(ready)) ms, \(action) \(ms(CACurrentMediaTime())) ms, ok \(ok)")
                }
            }
        }
    }

    /// Front-most normal-level window containing the point, ignoring our own panels.
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

    // MARK: Dragging the pin

    private var dragging = false
    private var lastBandOffset: CGFloat = 0
    private var dragOffset = CGVector.zero

    private var pressWasDrag = false

    private func dragBegan(at mouse: NSPoint) {
        pressWasDrag = true
        spikeLog("drag began: pin \(Self.fmt(panel.frame)), real \(Self.fmt(ax?.frame.map(Geometry.cocoa(fromCG:))))")
        lastBandOffset = 0
        dragging = true
        dragOffset = CGVector(dx: mouse.x - panel.frame.minX, dy: mouse.y - panel.frame.minY)
    }

    /// Moves the panel and the real window together on every mouse move, rather than letting
    /// the window server drag the panel and syncing afterwards (which lagged visibly).
    /// Positions from a fixed offset to the cursor so fast moves and display changes can't accumulate drift.
    private func drag(to mouse: NSPoint) {
        let origin = NSPoint(x: mouse.x - dragOffset.dx, y: mouse.y - dragOffset.dy)
        panel.setFrameOrigin(origin)
        moveRealWindow(to: NSRect(origin: origin, size: panel.frame.size), includingSize: false)
    }

    /// Dragging a real window's title bar brings it forward, so a pin drag does too.
    private func dragEnded() {
        dragging = false
        let dropped = panel.frame
        spikeLog("drag ended: pin \(Self.fmt(dropped)), real \(Self.fmt(ax?.frame.map(Geometry.cocoa(fromCG:))))")
        panelMovedOrResized()
        spikeLog("after sync: pin \(Self.fmt(panel.frame)), real \(Self.fmt(ax?.frame.map(Geometry.cocoa(fromCG:))))")
        for delay in [0.15, 0.5] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    spikeLog("+\(Int(delay * 1000)) ms: pin \(Self.fmt(self.panel.frame)), real \(Self.fmt(self.ax?.frame.map(Geometry.cocoa(fromCG:))))")
                }
            }
        }
        swapIn(pressAt: nil)
    }

    /// Cocoa (bottom-left origin) frames, so they compare directly with NSScreen frames in the log.
    private static func fmt(_ r: NSRect?) -> String {
        guard let r else { return "?" }
        return "(\(Int(r.minX)),\(Int(r.minY)) \(Int(r.width))x\(Int(r.height)) top \(Int(r.maxY)))"
    }

    /// Moves the real window under the pin. With `includingSize`, also resizes it and returns whether it
    /// ended up exactly there (position-only moves are for drags and skip the check to stay cheap).
    /// AppKit apps push their window back down, a moment after any move, if its top is above the menu bar of
    /// the screen holding most of it. Moving it there anyway makes the two fight (flicker), so in that band
    /// the real window goes to the nearest allowed spot: just below the menu bar, or just far enough up that
    /// most of it is on the screen above.
    @discardableResult
    private func moveRealWindow(to frame: NSRect, includingSize: Bool) -> Bool {
        guard let ax else { return true }
        var allowed = frame
        if let screen = Geometry.screen(for: frame), frame.maxY > screen.visibleFrame.maxY {
            var candidates = [screen.visibleFrame.maxY - frame.height]
            if let above = NSScreen.screens.first(where: {
                abs($0.frame.minY - screen.frame.maxY) < 1 && $0.frame.minX < frame.maxX && $0.frame.maxX > frame.minX
            }) {
                let mostlyAbove = above.frame.minY - frame.height / 2 + 1
                if mostlyAbove + frame.height <= above.visibleFrame.maxY { candidates.append(mostlyAbove) }
            }
            allowed.origin.y = candidates.min { abs($0 - frame.minY) < abs($1 - frame.minY) }!
        }
        let bandOffset = (allowed.minY - frame.minY).rounded()
        if dragging, abs(bandOffset - lastBandOffset) > 20 || (bandOffset == 0) != (lastBandOffset == 0) {
            spikeLog("band: pin \(Self.fmt(frame)) → real held at offset \(Int(bandOffset)), real now \(Self.fmt(ax.frame.map(Geometry.cocoa(fromCG:))))")
            lastBandOffset = bandOffset
        }
        let target = Geometry.cg(fromCocoa: allowed)
        guard includingSize else {
            ax.setPosition(target.origin)
            return true
        }
        ax.setFrame(target)
        return allowed == frame && (ax.frame.map { Geometry.roughlyEqual($0, target) } ?? false)
    }

    private func swapOut() {
        guard swappedIn else { return }
        swappedIn = false
        stopWatchingClicksElsewhere()
        onSwappedOut?(self)
        applyFrameRate()
        if let frame = ax?.frame { matchPanel(toCG: frame) }
        setMirrorVisible(true)
    }

    /// While another pin's real window is in use, this pin drops to normal level just below that window,
    /// so it can't cover it (or catch the press being handed to it).
    func setLowered(_ lowered: Bool, below windowID: CGWindowID? = nil) {
        panel.level = lowered ? .normal : .floating
        if lowered, let windowID { panel.order(.below, relativeTo: Int(windowID)) }
    }

    func bringToFront() {
        panel.orderFrontRegardless()
    }

    /// Hiding via alpha keeps the panel in the window list, so showing it again is a single-frame change
    /// rather than a reorder, which flashed.
    private func setMirrorVisible(_ visible: Bool) {
        panel.alphaValue = visible ? 1 : 0
        panel.ignoresMouseEvents = !visible
    }

    private var clickMonitor: Any?

    /// Shows the mirror the moment the user clicks outside the real window, instead of waiting for the
    /// other app's activation notification (by then that app has already drawn over the pin's spot).
    private func startWatchingClicksElsewhere() {
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.panel.frame.contains(NSEvent.mouseLocation) else { return }
                self.swapOut()
            }
        }
    }

    private func stopWatchingClicksElsewhere() {
        if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
        clickMonitor = nil
    }

    private func appActivated(pid: pid_t?) {
        guard swappedIn, let ax, pid != ax.pid else { return }
        swapOut()
    }

    private func sourceAppFocusChanged() {
        // The same app switching to another of its windows (e.g. Chrome's main window) also hands back to the pin.
        guard swappedIn, let ax, !ax.isFocusedWindow else { return }
        swapOut()
    }

    // MARK: Keeping pin and window aligned

    @objc private func panelMovedOrResized() {
        guard let ax, !dragging, !settling else { return }
        let target = Geometry.cg(fromCocoa: panel.frame)
        if let current = ax.frame, Geometry.roughlyEqual(current, target) { return }
        // The app or the system may still refuse the frame (e.g. too small); follow what it actually did.
        if !moveRealWindow(to: panel.frame, includingSize: true), !panel.inLiveResize, let actual = ax.frame {
            spikeLog("real window refused \(target), pin follows it to \(actual)")
            matchPanel(toCG: actual, animate: true)
        }
    }

    @objc private func panelEndedResize() {
        if let frame = ax?.frame {
            matchPanel(toCG: frame)
            updateCaptureSize(frame.size)
        }
    }

    private func sourceMovedOrResized() {
        guard !dragging, let frame = ax?.frame else { return }
        if !Geometry.roughlyEqual(Geometry.cocoa(fromCG: frame), panel.frame) {
            spikeLog("real window moved by itself to \(Self.fmt(Geometry.cocoa(fromCG: frame))); pin follows from \(Self.fmt(panel.frame))")
        }
        let sizeChanged = frame.size != Geometry.cg(fromCocoa: panel.frame).size
        matchPanel(toCG: frame)
        if sizeChanged { updateCaptureSize(frame.size) }
    }

    private var settling = false

    private func matchPanel(toCG frame: CGRect, animate: Bool = false) {
        let target = Geometry.cocoa(fromCG: frame)
        guard !Geometry.roughlyEqual(panel.frame, target) else { return }
        panel.contentAspectRatio = target.size
        // Following the real window must never push back on it: the panel's move notifications would
        // otherwise send the real window to this (by then stale) frame and fight the user's drag of it.
        // Animated setFrame also posts a notification per step, which this covers too.
        settling = true
        panel.setFrame(target, display: true, animate: animate)
        settling = false
    }

    // MARK: Closing

    func close() {
        guard !closed else { return }
        closed = true
        if swappedIn { onSwappedOut?(self) }
        fpsTimer?.invalidate()
        if let workspaceObserver { NSWorkspace.shared.notificationCenter.removeObserver(workspaceObserver) }
        NotificationCenter.default.removeObserver(self)
        ax?.stopObserving()
        stopWatchingClicksElsewhere()
        stream?.stopCapture { _ in }
        stream = nil
        panel.orderOut(nil)
        onClose?(self)
    }

    @objc private func closeFromMenu() { close() }

    // MARK: Helpers

    private static func postClick(at point: CGPoint) {
        post(.leftMouseDown, at: point)
        post(.leftMouseUp, at: point)
    }

    private static func post(_ type: CGEventType, at point: CGPoint) {
        let source = CGEventSource(stateID: .hidSystemState)
        CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: point, mouseButton: .left)?
            .post(tap: .cghidEventTap)
    }

    private func waitUntil(_ condition: @escaping () -> Bool, timeout: TimeInterval,
                           then done: @escaping (Bool) -> Void) {
        let deadline = CACurrentMediaTime() + timeout
        func check() {
            if condition() { done(true); return }
            if CACurrentMediaTime() > deadline { done(false); return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.005) { MainActor.assumeIsolated { check() } }
        }
        check()
    }
}

/// AppKit normally pushes a window down when its top is above the menu bar of the screen holding most of it,
/// which made the pin teleport while crossing between stacked displays. A pin goes wherever we put it.
final class PinPanel: NSPanel {
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

enum Geometry {
    private static var primaryHeight: CGFloat { NSScreen.screens.first?.frame.height ?? 0 }

    /// ScreenCaptureKit and AX use top-left-origin global coordinates; AppKit uses bottom-left of the primary screen.
    @MainActor static func cocoa(fromCG rect: CGRect) -> NSRect {
        NSRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    @MainActor static func cg(fromCocoa rect: NSRect) -> CGRect {
        CGRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    @MainActor static func cg(fromCocoa point: NSPoint) -> CGPoint {
        CGPoint(x: point.x, y: primaryHeight - point.y)
    }

    /// The screen holding most of the rect.
    @MainActor static func screen(for rect: NSRect) -> NSScreen? {
        NSScreen.screens.max { area($0.frame.intersection(rect)) < area($1.frame.intersection(rect)) }
    }

    private static func area(_ r: NSRect) -> CGFloat { r.isNull ? 0 : r.width * r.height }

    static func roughlyEqual(_ a: CGRect, _ b: CGRect) -> Bool {
        abs(a.minX - b.minX) < 1 && abs(a.minY - b.minY) < 1 && abs(a.width - b.width) < 1 && abs(a.height - b.height) < 1
    }
}

final class MirrorView: NSView {
    let imageLayer = CALayer()
    let fpsLabel = NSTextField(labelWithString: "")
    /// Called with the click location in top-left-origin global coordinates.
    /// Called on every left mouse-down, before knowing whether it's a click or a drag.
    var onPress: ((CGPoint) -> Void)?
    /// Drag callbacks get the cursor in AppKit screen coordinates.
    var onDragBegan: ((NSPoint) -> Void)?
    var onDrag: ((NSPoint) -> Void)?
    var onDragEnded: (() -> Void)?
    private var mouseDownLocation: NSPoint?
    private var downInDragStrip = false
    private var isDragging = false

    /// The top strip (where a title bar or tab strip usually is) drags the pin once the mouse moves;
    /// a plain click there, or anywhere else, is a click on the real window.
    static let dragStripHeight: CGFloat = 32
    static let dragThreshold: CGFloat = 3

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        imageLayer.contentsGravity = .resizeAspect
        // YUV frames have no alpha, so the pin would be a solid rectangle exactly over the real window.
        // macOS then reports the real window as fully occluded and Chrome stops drawing video into it.
        // Rounded (transparent) corners keep it "visible", and match macOS window corners.
        imageLayer.cornerRadius = 12
        imageLayer.cornerCurve = .continuous
        imageLayer.masksToBounds = true
        layer?.addSublayer(imageLayer)

        fpsLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
        fpsLabel.textColor = .white
        fpsLabel.drawsBackground = true
        fpsLabel.backgroundColor = NSColor.black.withAlphaComponent(0.6)
        fpsLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(fpsLabel)
        NSLayoutConstraint.activate([
            fpsLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            fpsLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        let local = convert(event.locationInWindow, from: nil)
        downInDragStrip = local.y > bounds.height - Self.dragStripHeight
        mouseDownLocation = NSEvent.mouseLocation
        isDragging = false
        onPress?(Geometry.cg(fromCocoa: NSEvent.mouseLocation))
    }

    override func mouseDragged(with event: NSEvent) {
        guard downInDragStrip, let start = mouseDownLocation else { return }
        let now = NSEvent.mouseLocation
        if !isDragging {
            guard hypot(now.x - start.x, now.y - start.y) >= Self.dragThreshold else { return }
            isDragging = true
            onDragBegan?(start)
        }
        onDrag?(now)
    }

    override func mouseUp(with event: NSEvent) {
        defer { mouseDownLocation = nil; isDragging = false }
        if isDragging { onDragEnded?() }
    }

    /// The press was handed to the real window, which will get the mouse-up instead of us.
    func cancelTracking() {
        mouseDownLocation = nil
        isDragging = false
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        imageLayer.frame = bounds
        CATransaction.commit()
    }
}

/// Receives frames on a background queue and puts them straight on the mirror's layer. Core Animation
/// allows layer changes from any thread inside an explicit transaction; skipping a hop to the main thread
/// per frame matters with several pins at 60 fps.
final class FrameOutput: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    let queue = DispatchQueue(label: "TackSpike.frames", qos: .userInteractive)
    /// Set once before capture starts.
    nonisolated(unsafe) var layer: CALayer?
    var onStop: (@Sendable (String) -> Void)?
    private let frameCount = Mutex(0)

    func takeFrameCount() -> Int {
        frameCount.withLock { count in
            defer { count = 0 }
            return count
        }
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, sampleBuffer.isValid,
              let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let rawStatus = attachments.first?[.status] as? Int,
              SCFrameStatus(rawValue: rawStatus) == .complete,
              let pixelBuffer = sampleBuffer.imageBuffer,
              let surface = CVPixelBufferGetIOSurface(pixelBuffer)?.takeUnretainedValue()
        else { return }
        recordDirtyRects(attachments.first?[.dirtyRects] as? [NSDictionary])
        let hashStart = CACurrentMediaTime()
        let hash = Self.fingerprint(surface)
        statsHashTime += CACurrentMediaTime() - hashStart
        // Redrawing the pin makes macOS re-capture the window underneath (a feedback loop that keeps static
        // windows at full frame rate), and dirty rects always report the whole window. So skip identical frames.
        guard hash != lastHash else {
            unchangedFrames += 1
            if unchangedFrames == Self.framesBeforeIdle { onIdleChanged?(true) }
            return
        }
        lastHash = hash
        if unchangedFrames >= Self.framesBeforeIdle { onIdleChanged?(false) }
        unchangedFrames = 0
        statsShown += 1
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer?.contents = surface
        CATransaction.commit()
        frameCount.withLock { $0 += 1 }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        onStop?(error.localizedDescription)
    }

    private var lastHash: UInt64 = 0
    private var unchangedFrames = 0
    private static let framesBeforeIdle = 30
    /// macOS sends every captured window a frame whenever anything on its display updates, so an unchanged window
    /// still arrives at full rate. After ~0.5 s without change the mirror asks for fewer frames.
    var onIdleChanged: (@Sendable (Bool) -> Void)?

    /// Hash of every 8th row of the luma plane (YUV) or image (BGRA); four lanes to keep the multiply chains short.
    /// A line of text spans many rows, so sampling still catches typing; it's ~8x cheaper than every row.
    private static func fingerprint(_ surface: IOSurface) -> UInt64 {
        IOSurfaceLock(surface, .readOnly, nil)
        defer { IOSurfaceUnlock(surface, .readOnly, nil) }
        let planar = IOSurfaceGetPlaneCount(surface) > 0
        let base = planar ? IOSurfaceGetBaseAddressOfPlane(surface, 0) : IOSurfaceGetBaseAddress(surface)
        let bytesPerRow = planar ? IOSurfaceGetBytesPerRowOfPlane(surface, 0) : IOSurfaceGetBytesPerRow(surface)
        let height = planar ? IOSurfaceGetHeightOfPlane(surface, 0) : IOSurfaceGetHeight(surface)
        let rowBytes = planar ? IOSurfaceGetWidthOfPlane(surface, 0) : IOSurfaceGetWidth(surface) * 4
        let words = rowBytes / 32 * 4
        let prime: UInt64 = 0x100000001b3
        var h0: UInt64 = 0xcbf29ce484222325, h1 = h0 &+ 1, h2 = h0 &+ 2, h3 = h0 &+ 3
        for y in stride(from: 0, to: height, by: 8) {
            let row = (base + y * bytesPerRow).assumingMemoryBound(to: UInt64.self)
            var x = 0
            while x < words {
                h0 = (h0 ^ row[x]) &* prime
                h1 = (h1 ^ row[x + 1]) &* prime
                h2 = (h2 ^ row[x + 2]) &* prime
                h3 = (h3 ^ row[x + 3]) &* prime
                x += 4
            }
        }
        return h0 ^ (h1 &* 3) ^ (h2 &* 5) ^ (h3 &* 7)
    }

    // MARK: Diagnostics: what actually changes in frames of "static" windows

    var name = ""
    private var statsStart = CACurrentMediaTime()
    private var statsFrames = 0
    private var statsEmpty = 0
    private var statsUnion = CGRect.null
    private var statsArea: CGFloat = 0
    private var statsShown = 0
    private var statsHashTime: Double = 0

    /// Called on the capture queue only.
    private func recordDirtyRects(_ dicts: [NSDictionary]?) {
        let rects = (dicts ?? []).compactMap { CGRect(dictionaryRepresentation: $0) }
        statsFrames += 1
        if rects.isEmpty { statsEmpty += 1 }
        for r in rects {
            statsUnion = statsUnion.union(r)
            statsArea += r.width * r.height
        }
        let now = CACurrentMediaTime()
        guard now - statsStart >= 2 else { return }
        let u = statsUnion.isNull ? "none" : "\(Int(statsUnion.minX)),\(Int(statsUnion.minY)) \(Int(statsUnion.width))x\(Int(statsUnion.height))"
        let avgArea = statsFrames > 0 ? Int(statsArea / CGFloat(statsFrames)) : 0
        let hashUs = statsFrames > 0 ? Int(statsHashTime / Double(statsFrames) * 1_000_000) : 0
        spikeLog("frames[\(name)]: \(statsFrames / 2)/s received, \(statsShown / 2)/s shown, hash \(hashUs) µs, dirty union \(u), avg dirty px \(avgArea)")
        statsStart = now; statsFrames = 0; statsEmpty = 0; statsUnion = .null; statsArea = 0; statsShown = 0; statsHashTime = 0
    }
}
