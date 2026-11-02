import AppKit
import SwiftUI

/// The pin manager that grows out of the hardware notch (REQUIREMENTS section 4). One fixed-size transparent
/// panel sits above the menu bar; the black shape animates inside it, so expanding never resizes a window.
/// Clicks pass through everywhere except over the expanded shape.
@MainActor
final class NotchController {
    private let model = NotchModel()
    private let pins: PinManager
    private let panel: NotchPanel
    private let notchRect: NSRect
    private var monitors: [Any] = []
    private var collapseWork: DispatchWorkItem?

    /// nil on Macs or setups without a notched screen; the menu bar is the manager there.
    init?(pins: PinManager) {
        guard let screen = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }),
              let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea else {
            tackLog("notch: no notched screen")
            return nil
        }
        self.pins = pins
        let height = screen.safeAreaInsets.top
        notchRect = NSRect(x: left.maxX, y: screen.frame.maxY - height, width: right.minX - left.maxX, height: height)
        model.notchSize = notchRect.size
        tackLog("notch: \(Int(notchRect.width))x\(Int(notchRect.height)) on \(screen.localizedName)")

        let size = NSSize(width: NotchModel.expandedWidth, height: NotchModel.maxExpandedHeight)
        let frame = NSRect(x: notchRect.midX - size.width / 2, y: screen.frame.maxY - size.height,
                           width: size.width, height: size.height)
        panel = NotchPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel],
                           backing: .buffered, defer: false)
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3) // above the menu bar
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true

        let actions = NotchActions(
            jump: { [weak self] id in self?.withPin(id) { self?.pins.jump(to: $0) } },
            unpin: { [weak self] id in self?.withPin(id) { self?.pins.unpin($0) } },
            move: { [weak self] id, forward in self?.withPin(id) { self?.pins.move($0, forward: forward) } },
            reorder: { [weak self] from, to in self?.pins.move(fromOffsets: IndexSet(integer: from), toOffset: to) },
            loadCandidates: { [weak self] in self?.loadCandidates() },
            pinCandidate: { [weak self] candidate in
                self?.pins.pin(candidate)
                self?.model.showingCandidates = false
            }
        )
        panel.contentView = FirstMouseHostingView(rootView: NotchView(model: model, actions: actions))
        panel.setFrame(frame, display: true)
        panel.orderFrontRegardless()

        let onMove: (NSEvent) -> Void = { [weak self] _ in MainActor.assumeIsolated { self?.mouseMoved() } }
        monitors.append(NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged], handler: onMove) as Any)
        monitors.append(NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { event in
            onMove(event)
            return event
        } as Any)
        update()
    }

    /// Called when the screen setup changes and this notch may no longer exist.
    func tearDown() {
        for monitor in monitors { NSEvent.removeMonitor(monitor) }
        monitors = []
        panel.orderOut(nil)
    }

    func update() {
        withAnimation(Motion.spring(duration: 0.35, bounce: 0.15)) {
            model.rows = pins.pins.map { pin in
                NotchModel.Row(id: pin.windowID, icon: pin.appIcon, title: pin.title,
                               subtitle: pin.title == pin.appName ? nil : pin.appName,
                               minimized: pin.isMinimized)
            }
            model.showsManyPinsWarning = pins.showsManyPinsWarning
        }
    }

    private func withPin(_ id: CGWindowID, _ body: (Pin) -> Void) {
        if let pin = pins.pins.first(where: { $0.windowID == id }) { body(pin) }
    }

    private func loadCandidates() {
        model.loadingCandidates = true
        Task {
            let candidates = await pins.candidates()
            withAnimation(Motion.spring(duration: 0.3, bounce: 0.15)) {
                model.candidates = candidates
                model.loadingCandidates = false
            }
        }
    }

    // MARK: Hover

    /// Cocoa screen rect of the visible black shape for a given size, hanging from the top of the screen.
    private func shapeRect(_ size: CGSize) -> NSRect {
        NSRect(x: notchRect.midX - size.width / 2, y: notchRect.maxY - size.height, width: size.width, height: size.height)
    }

    private func mouseMoved() {
        let mouse = NSEvent.mouseLocation
        let zone = shapeRect(model.expanded ? model.expandedSize : model.collapsedSize).insetBy(dx: -2, dy: -2)
        let inside = zone.contains(mouse)
        // Only catch clicks over the expanded shape; everywhere else (including the rest of the panel) passes through.
        panel.ignoresMouseEvents = !(inside && model.expanded)

        if inside {
            collapseWork?.cancel()
            collapseWork = nil
            if !model.expanded { setExpanded(true) }
        } else if model.expanded, collapseWork == nil {
            let work = DispatchWorkItem { [weak self] in
                MainActor.assumeIsolated {
                    self?.collapseWork = nil
                    self?.setExpanded(false)
                }
            }
            collapseWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: work)
        }
    }

    private func setExpanded(_ expanded: Bool) {
        withAnimation(Motion.spring(duration: 0.35, bounce: 0.2)) {
            model.expanded = expanded
            if !expanded { model.showingCandidates = false }
        }
        panel.ignoresMouseEvents = !expanded
    }
}

/// Can become key (for keyboard reordering) without activating Tack, and is never pushed below the menu bar.
final class NotchPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

/// The notch panel belongs to a background app, so without this the first click would only make it key.
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
