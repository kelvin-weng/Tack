import AppKit
import SwiftUI

/// AppKit normally pushes a window down when its top is above the menu bar of the screen holding most of it,
/// which made pins teleport when crossing between stacked displays. A pin goes wherever we put it.
final class PinPanel: NSPanel {
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

/// Shows the mirror and turns mouse input into pin gestures: a press (handed to the real window),
/// or a drag from the top edge (moves the pin). Also hosts the hover toolbar and the "unavailable" overlay.
final class PinView: NSView {
    let imageLayer = CALayer()
    /// Thin accent border with a soft inner glow (F14). Only the edge is drawn, so the corners stay see-through.
    private let borderLayer = CALayer()

    var showsBorder = true {
        didSet { borderLayer.isHidden = !showsBorder }
    }

    var borderColor = PinSettings.defaultBorderColor {
        didSet {
            borderLayer.borderColor = borderColor.withAlphaComponent(0.75).cgColor
            borderLayer.shadowColor = borderColor.cgColor
        }
    }

    /// Press location in CG coordinates, and whether it was in the drag area.
    var onPress: ((CGPoint, Bool) -> Void)?
    /// Drag callbacks get the cursor in AppKit screen coordinates.
    var onDragBegan: ((NSPoint) -> Void)?
    var onDrag: ((NSPoint) -> Void)?
    var onDragEnded: (() -> Void)?

    /// The top strip (where a title or tab bar usually is) drags the pin once the mouse moves;
    /// a plain click there, or anywhere else, goes to the real window.
    static let dragStripHeight: CGFloat = 32
    private static let dragThreshold: CGFloat = 3
    /// Rounded, see-through corners: a pin that fully and opaquely covers its window makes macOS treat
    /// the window as hidden, and apps like Chrome stop drawing video into it. Never go below this.
    static let minimumCornerRadius: CGFloat = 12
    private var cornerRadius = PinView.minimumCornerRadius
    /// The window's own corners (Finder's are much rounder than most). The live capture has no transparency,
    /// so without this the window's see-through corners would show as black.
    private let cornerMask = CALayer()

    func useCorners(_ corners: WindowCapture.Corners) {
        cornerMask.contents = corners.mask
        cornerMask.contentsScale = corners.scale
        cornerMask.contentsCenter = corners.contentsCenter
        imageLayer.mask = cornerMask
        cornerRadius = max(Self.minimumCornerRadius, corners.radius)
        borderLayer.cornerRadius = cornerRadius
        overlay.layer?.cornerRadius = cornerRadius
        needsLayout = true
    }

    private var mouseDownLocation: NSPoint?
    private var downInDragStrip = false
    private var isDragging = false

    private let toolbar: NSHostingView<PinToolbar>
    private let overlay: NSHostingView<UnavailableOverlay>

    init(frame: NSRect, onUnpin: @escaping () -> Void, onBringBack: @escaping () -> Void) {
        toolbar = NSHostingView(rootView: PinToolbar(unpin: onUnpin))
        overlay = NSHostingView(rootView: UnavailableOverlay(bringBack: onBringBack))
        super.init(frame: frame)
        wantsLayer = true
        imageLayer.contentsGravity = .resizeAspect
        // Stays at the minimum: it sits inside any rounder window corner, and the mask does the rest.
        imageLayer.cornerRadius = Self.minimumCornerRadius
        imageLayer.cornerCurve = .continuous
        imageLayer.masksToBounds = true
        layer?.addSublayer(imageLayer)

        borderLayer.cornerRadius = cornerRadius
        borderLayer.cornerCurve = .continuous
        borderLayer.borderWidth = 1
        borderLayer.borderColor = borderColor.withAlphaComponent(0.75).cgColor
        borderLayer.shadowColor = borderColor.cgColor
        borderLayer.shadowOpacity = 0.6
        borderLayer.shadowRadius = 4
        borderLayer.shadowOffset = .zero
        layer?.addSublayer(borderLayer)

        overlay.translatesAutoresizingMaskIntoConstraints = false
        overlay.isHidden = true
        overlay.wantsLayer = true
        overlay.layer?.cornerRadius = cornerRadius
        overlay.layer?.cornerCurve = .continuous
        overlay.layer?.masksToBounds = true
        addSubview(overlay)
        toolbar.translatesAutoresizingMaskIntoConstraints = false
        toolbar.alphaValue = 0
        toolbar.isHidden = true
        addSubview(toolbar)
        NSLayoutConstraint.activate([
            overlay.leadingAnchor.constraint(equalTo: leadingAnchor),
            overlay.trailingAnchor.constraint(equalTo: trailingAnchor),
            overlay.topAnchor.constraint(equalTo: topAnchor),
            overlay.bottomAnchor.constraint(equalTo: bottomAnchor),
            toolbar.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            toolbar.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: Unavailable state

    var isUnavailable: Bool {
        get { !overlay.isHidden }
        set { overlay.isHidden = !newValue }
    }

    // MARK: Hover toolbar

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        // activeAlways: Tack is an agent app and is almost never the active app.
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) { setToolbarVisible(true) }
    override func mouseExited(with event: NSEvent) { setToolbarVisible(false) }

    func setToolbarVisible(_ visible: Bool) {
        if visible { toolbar.isHidden = false }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.15
            toolbar.animator().alphaValue = visible ? 1 : 0
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                // Hidden views aren't hit-tested, so a faded-out toolbar can't swallow clicks.
                if let self, self.toolbar.alphaValue == 0 { self.toolbar.isHidden = true }
            }
        })
    }

    // MARK: Gestures

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        let local = convert(event.locationInWindow, from: nil)
        downInDragStrip = local.y > bounds.height - Self.dragStripHeight
        mouseDownLocation = NSEvent.mouseLocation
        isDragging = false
        onPress?(Geometry.cg(fromCocoa: NSEvent.mouseLocation), downInDragStrip)
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

    /// The press was handed to the real window, which gets the rest of the gesture instead of us.
    func cancelTracking() {
        mouseDownLocation = nil
        isDragging = false
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        imageLayer.frame = bounds
        cornerMask.frame = imageLayer.bounds
        borderLayer.frame = bounds
        CATransaction.commit()
    }
}

private struct PinToolbar: View {
    let unpin: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Glyph.image(size: 12)
                .foregroundStyle(.tint)
                .accessibilityLabel("Tack")
            Button(action: unpin) {
                Image(systemName: "pin.slash")
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 22, height: 22)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .help("Unpin")
            .accessibilityLabel("Unpin")
        }
        .padding(.leading, 9)
        .padding(.trailing, 4)
        .padding(.vertical, 3)
        .glassEffect(.regular, in: .capsule)
    }
}

private struct UnavailableOverlay: View {
    let bringBack: () -> Void

    var body: some View {
        ZStack {
            Rectangle().fill(.black.opacity(0.55))
            VStack(spacing: 10) {
                Image(systemName: "arrow.down.right.and.arrow.up.left")
                    .font(.system(size: 24, weight: .medium))
                Text("This window is minimised")
                    .font(.headline)
                Button("Bring It Back", action: bringBack)
                    .buttonStyle(ProminentButtonStyle())
            }
            .foregroundStyle(.white)
            .padding(20)
            .glassEffect(.regular, in: .rect(cornerRadius: 18))
        }
    }
}
