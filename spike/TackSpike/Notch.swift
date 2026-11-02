import AppKit
import SwiftUI

/// Black panel that grows out of the hardware notch: collapsed shows a glyph and pin count beside the notch,
/// hovering expands it downward into a list of pins.
@MainActor
final class NotchController {
    let model = NotchModel()
    private var panel: NSPanel?
    private var monitors: [Any] = []
    private var notchRect: NSRect = .zero
    private var collapseWork: DispatchWorkItem?

    init() {
        guard let screen = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }),
              let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea else {
            spikeLog("notch: no notched screen found")
            return
        }
        let height = screen.safeAreaInsets.top
        notchRect = NSRect(x: left.maxX, y: screen.frame.maxY - height, width: right.minX - left.maxX, height: height)
        model.notchSize = notchRect.size
        spikeLog("notch: \(Int(notchRect.width))x\(Int(notchRect.height)) at x \(Int(notchRect.minX)) on \(screen.localizedName)")

        // Fixed at the largest size it can expand to, so expanding is a SwiftUI animation, not a window resize.
        let size = NSSize(width: NotchModel.expandedWidth, height: NotchModel.maxExpandedHeight)
        let frame = NSRect(x: notchRect.midX - size.width / 2, y: screen.frame.maxY - size.height,
                           width: size.width, height: size.height)
        let panel = UnconstrainedPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel],
                                       backing: .buffered, defer: false)
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3) // above the menu bar
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        panel.contentView = NSHostingView(rootView: NotchView(model: model))
        panel.setFrame(frame, display: true)
        panel.orderFrontRegardless()
        self.panel = panel

        let onMove: (NSEvent) -> Void = { [weak self] _ in MainActor.assumeIsolated { self?.mouseMoved() } }
        monitors.append(NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged], handler: onMove) as Any)
        monitors.append(NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { event in
            onMove(event)
            return event
        } as Any)
    }

    func update(pins: [Mirror]) {
        withAnimation(.spring(duration: 0.35, bounce: 0.15)) {
            model.rows = pins.map { NotchModel.Row(id: ObjectIdentifier($0), icon: $0.appIcon, app: $0.appName, title: $0.title) }
        }
    }

    // MARK: Hover

    /// Cocoa screen rect of the visible black shape for a given size, hanging from the top of the screen.
    private func shapeRect(_ size: CGSize) -> NSRect {
        NSRect(x: notchRect.midX - size.width / 2, y: notchRect.maxY - size.height, width: size.width, height: size.height)
    }

    private func mouseMoved() {
        guard let panel else { return }
        let mouse = NSEvent.mouseLocation
        let zone = shapeRect(model.expanded ? model.expandedSize : model.collapsedSize).insetBy(dx: -2, dy: -2)
        let inside = zone.contains(mouse)
        // Only catch clicks over the expanded shape; everywhere else (including the transparent rest of the panel) passes through.
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
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
        }
    }

    private func setExpanded(_ expanded: Bool) {
        withAnimation(.spring(duration: 0.35, bounce: 0.2)) { model.expanded = expanded }
        panel?.ignoresMouseEvents = !expanded
    }
}

final class UnconstrainedPanel: NSPanel {
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

@MainActor
@Observable
final class NotchModel {
    struct Row: Identifiable {
        let id: ObjectIdentifier
        let icon: NSImage?
        let app: String
        let title: String
    }

    var rows: [Row] = []
    var expanded = false
    var notchSize = CGSize(width: 185, height: 32)

    static let wing: CGFloat = 36
    static let expandedWidth: CGFloat = 440
    static let rowHeight: CGFloat = 40
    static let maxRows = 8
    static let bottomPadding: CGFloat = 14
    static var maxExpandedHeight: CGFloat { 40 + CGFloat(maxRows) * rowHeight + bottomPadding }

    /// With nothing pinned the shape is exactly the notch, so the notch looks normal.
    var collapsedSize: CGSize {
        // + 2 × the collapsed top flare, so the shape's body lines up exactly with the hardware notch.
        let base = notchSize.width + 12
        return rows.isEmpty ? CGSize(width: base, height: notchSize.height)
                            : CGSize(width: base + 2 * Self.wing, height: notchSize.height)
    }

    var expandedSize: CGSize {
        let visibleRows = CGFloat(min(max(rows.count, 1), Self.maxRows))
        return CGSize(width: Self.expandedWidth, height: notchSize.height + 6 + visibleRows * Self.rowHeight + Self.bottomPadding)
    }
}

struct NotchView: View {
    let model: NotchModel
    private let accent = Color(red: 0, green: 0xCE / 255, blue: 0xC8 / 255)

    var body: some View {
        let size = model.expanded ? model.expandedSize : model.collapsedSize
        ZStack(alignment: .top) {
            NotchShape(topRadius: model.expanded ? 10 : 6, bottomRadius: model.expanded ? 24 : 10)
                .fill(.black)
            VStack(spacing: 0) {
                header
                if model.expanded {
                    list.transition(.opacity.combined(with: .offset(y: -8)))
                }
            }
            .padding(.horizontal, model.expanded ? 26 : 14)
        }
        .frame(width: size.width, height: size.height, alignment: .top)
        .clipped()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .foregroundStyle(.white)
    }

    /// Sits beside the hardware notch: glyph on the left, count on the right.
    private var header: some View {
        HStack {
            if !model.rows.isEmpty || model.expanded {
                Image(systemName: "pin.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(accent)
                Spacer(minLength: model.notchSize.width)
                Text("\(model.rows.count)")
                    .font(.system(size: 13, weight: .semibold).monospacedDigit())
            }
        }
        .frame(height: model.notchSize.height)
    }

    private var list: some View {
        VStack(spacing: 0) {
            if model.rows.isEmpty {
                Text("No pins yet")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.6))
                    .frame(height: NotchModel.rowHeight)
            }
            ForEach(model.rows.prefix(NotchModel.maxRows)) { row in
                HStack(spacing: 10) {
                    if let icon = row.icon {
                        Image(nsImage: icon).resizable().frame(width: 22, height: 22)
                    }
                    VStack(alignment: .leading, spacing: 1) {
                        Text(row.title).font(.system(size: 13, weight: .medium)).lineLimit(1)
                        Text(row.app).font(.system(size: 11)).foregroundStyle(.white.opacity(0.55)).lineLimit(1)
                    }
                    Spacer()
                    Image(systemName: "line.3.horizontal")
                        .foregroundStyle(.white.opacity(0.45))
                }
                .frame(height: NotchModel.rowHeight)
            }
        }
        .padding(.top, 6)
    }
}

/// The hardware notch's outline: small outward flares where it meets the top edge, rounded bottom corners.
struct NotchShape: Shape {
    var topRadius: CGFloat
    var bottomRadius: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(topRadius, bottomRadius) }
        set { topRadius = newValue.first; bottomRadius = newValue.second }
    }

    func path(in rect: CGRect) -> Path {
        let t = topRadius, b = min(bottomRadius, rect.height / 2)
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addQuadCurve(to: CGPoint(x: rect.minX + t, y: rect.minY + t), control: CGPoint(x: rect.minX + t, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.minX + t, y: rect.maxY - b))
        p.addQuadCurve(to: CGPoint(x: rect.minX + t + b, y: rect.maxY), control: CGPoint(x: rect.minX + t, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.maxX - t - b, y: rect.maxY))
        p.addQuadCurve(to: CGPoint(x: rect.maxX - t, y: rect.maxY - b), control: CGPoint(x: rect.maxX - t, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.maxX - t, y: rect.minY + t))
        p.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY), control: CGPoint(x: rect.maxX - t, y: rect.minY))
        p.closeSubpath()
        return p
    }
}
