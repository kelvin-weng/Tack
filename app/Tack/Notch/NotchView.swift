import AppKit
import SwiftUI

@MainActor
@Observable
final class NotchModel {
    struct Row: Identifiable {
        let id: CGWindowID
        let icon: NSImage?
        let title: String
        /// App name, when it adds something to the title.
        let subtitle: String?
        let minimized: Bool
    }

    var rows: [Row] = []
    var expanded = false
    var notchSize = CGSize(width: 185, height: 32)
    var showingCandidates = false
    var loadingCandidates = false
    var candidates: [PinManager.Candidate] = []
    var showsManyPinsWarning = false

    static let wing: CGFloat = 36
    static let expandedWidth: CGFloat = 440
    static let rowHeight: CGFloat = 44
    static let footerHeight: CGFloat = 40
    static let candidateHeight: CGFloat = 34
    static let warningHeight: CGFloat = 30
    static let maxVisibleRows = 8
    static let maxVisibleCandidates = 6
    static let bottomPadding: CGFloat = 12
    static var maxExpandedHeight: CGFloat {
        40 + CGFloat(maxVisibleRows) * rowHeight + warningHeight + footerHeight + CGFloat(maxVisibleCandidates) * candidateHeight + bottomPadding + 10
    }

    /// With nothing pinned the shape is exactly the notch (plus its top flares), so the notch looks normal.
    var collapsedSize: CGSize {
        let base = notchSize.width + 12
        return rows.isEmpty ? CGSize(width: base, height: notchSize.height)
                            : CGSize(width: base + 2 * Self.wing, height: notchSize.height)
    }

    var rowsHeight: CGFloat { CGFloat(min(max(rows.count, 1), Self.maxVisibleRows)) * Self.rowHeight }

    var candidatesHeight: CGFloat {
        guard showingCandidates else { return 0 }
        let count = loadingCandidates || candidates.isEmpty ? 1 : min(candidates.count, Self.maxVisibleCandidates)
        return CGFloat(count) * Self.candidateHeight + 6
    }

    var expandedSize: CGSize {
        CGSize(width: Self.expandedWidth,
               height: notchSize.height + 6 + rowsHeight + (showsManyPinsWarning ? Self.warningHeight : 0)
                   + Self.footerHeight + candidatesHeight + Self.bottomPadding)
    }
}

struct NotchActions {
    let jump: (CGWindowID) -> Void
    let unpin: (CGWindowID) -> Void
    /// forward = towards the front of the stack.
    let move: (CGWindowID, Bool) -> Void
    /// Front-to-back offsets, as in `Array.move(fromOffsets:toOffset:)`.
    let reorder: (Int, Int) -> Void
    let loadCandidates: () -> Void
    let pinCandidate: (PinManager.Candidate) -> Void
}

struct NotchView: View {
    let model: NotchModel
    let actions: NotchActions

    @State private var draggedID: CGWindowID?
    @State private var dragTranslation: CGFloat = 0

    var body: some View {
        let size = model.expanded ? model.expandedSize : model.collapsedSize
        ZStack(alignment: .top) {
            NotchShape(topRadius: model.expanded ? 10 : 6, bottomRadius: model.expanded ? 24 : 10)
                .fill(.black)
            VStack(spacing: 0) {
                header
                if model.expanded {
                    VStack(spacing: 0) {
                        rows
                        if model.showsManyPinsWarning { manyPinsWarning }
                        footer
                        if model.showingCandidates { candidates }
                    }
                    .padding(.top, 6)
                    .transition(.opacity.combined(with: .offset(y: -8)))
                }
            }
            .padding(.horizontal, model.expanded ? 22 : 14)
        }
        .frame(width: size.width, height: size.height, alignment: .top)
        .clipped()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .foregroundStyle(.white)
        .environment(\.colorScheme, .dark)
    }

    /// Sits beside the hardware notch: glyph on the left, pin count on the right.
    private var header: some View {
        HStack {
            if !model.rows.isEmpty || model.expanded {
                Glyph.image(size: 13)
                    .foregroundStyle(.tint)
                    .accessibilityLabel("Tack")
                Spacer(minLength: model.notchSize.width)
                Text("\(model.rows.count)")
                    .font(.system(size: 13, weight: .semibold).monospacedDigit())
                    .accessibilityLabel("\(model.rows.count) pinned")
            }
        }
        .frame(height: model.notchSize.height)
    }

    // MARK: Pin rows

    @ViewBuilder
    private var rows: some View {
        if model.rows.isEmpty {
            Text("No windows pinned")
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.6))
                .frame(maxWidth: .infinity, minHeight: NotchModel.rowHeight)
        } else {
            ScrollView(.vertical) {
                VStack(spacing: 0) {
                    ForEach(Array(model.rows.enumerated()), id: \.element.id) { index, row in
                        PinRowView(row: row, actions: actions, isFirst: index == 0, isLast: index == model.rows.count - 1)
                            .frame(height: NotchModel.rowHeight)
                            .offset(y: offset(forRowAt: index))
                            .zIndex(draggedID == row.id ? 1 : 0)
                            .gesture(reorderGesture(for: row, at: index))
                    }
                }
                .animation(Motion.spring(duration: 0.25, bounce: 0.1), value: targetIndex)
            }
            .scrollDisabled(model.rows.count <= NotchModel.maxVisibleRows)
            .frame(height: model.rowsHeight)
        }
    }

    private var draggedIndex: Int? {
        draggedID.flatMap { id in model.rows.firstIndex { $0.id == id } }
    }

    /// Where the dragged row would land if dropped now.
    private var targetIndex: Int? {
        guard let from = draggedIndex else { return nil }
        let moved = Int((dragTranslation / NotchModel.rowHeight).rounded())
        return min(max(from + moved, 0), model.rows.count - 1)
    }

    /// The dragged row follows the pointer; the rows it passes slide out of its way.
    private func offset(forRowAt index: Int) -> CGFloat {
        guard let from = draggedIndex, let to = targetIndex else { return 0 }
        if index == from { return dragTranslation }
        if from < to, (from + 1...to).contains(index) { return -NotchModel.rowHeight }
        if to < from, (to..<from).contains(index) { return NotchModel.rowHeight }
        return 0
    }

    private func reorderGesture(for row: NotchModel.Row, at index: Int) -> some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                draggedID = row.id
                dragTranslation = value.translation.height
            }
            .onEnded { _ in
                if let to = targetIndex, to != index {
                    actions.reorder(index, to > index ? to + 1 : to)
                }
                draggedID = nil
                dragTranslation = 0
            }
    }

    private var manyPinsWarning: some View {
        Label("Lots of pins can slow your Mac down.", systemImage: "exclamationmark.triangle.fill")
            .font(.system(size: 12))
            .foregroundStyle(.yellow)
            .frame(maxWidth: .infinity, minHeight: NotchModel.warningHeight, alignment: .leading)
            .padding(.leading, 6)
    }

    // MARK: Pin a window (F2)

    private var footer: some View {
        Button {
            withAnimation(Motion.spring(duration: 0.3, bounce: 0.15)) { model.showingCandidates.toggle() }
            if model.showingCandidates { actions.loadCandidates() }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(.tint)
                Text("Pin a Window")
                    .font(.system(size: 13, weight: .medium))
                Spacer()
                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .semibold))
                    .rotationEffect(.degrees(model.showingCandidates ? 180 : 0))
                    .foregroundStyle(.white.opacity(0.5))
            }
            .frame(height: NotchModel.footerHeight)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Shows windows you can pin")
    }

    @ViewBuilder
    private var candidates: some View {
        Group {
            if model.loadingCandidates {
                ProgressView().controlSize(.small)
                    .frame(maxWidth: .infinity, minHeight: NotchModel.candidateHeight)
            } else if model.candidates.isEmpty {
                Text("No other windows on screen")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.6))
                    .frame(maxWidth: .infinity, minHeight: NotchModel.candidateHeight)
            } else {
                ScrollView(.vertical) {
                    VStack(spacing: 0) {
                        ForEach(model.candidates) { candidate in
                            CandidateRowView(candidate: candidate) { actions.pinCandidate(candidate) }
                        }
                    }
                }
                .frame(height: CGFloat(min(model.candidates.count, NotchModel.maxVisibleCandidates)) * NotchModel.candidateHeight)
            }
        }
        .padding(.leading, 26)
        .padding(.bottom, 6)
    }
}

private struct PinRowView: View {
    let row: NotchModel.Row
    let actions: NotchActions
    let isFirst: Bool
    let isLast: Bool
    @State private var hovering = false
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 10) {
            if let icon = row.icon {
                Image(nsImage: icon).resizable().frame(width: 22, height: 22)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(row.title).font(.system(size: 13, weight: .medium)).lineLimit(1)
                if let subtitle = row.subtitle {
                    Text(subtitle).font(.system(size: 11)).foregroundStyle(.white.opacity(0.55)).lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            if row.minimized {
                Text("Minimised").font(.system(size: 11)).foregroundStyle(.white.opacity(0.55))
            }
            Button { actions.unpin(row.id) } label: {
                Image(systemName: "pin.slash")
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 24, height: 22)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .help("Unpin")
            .accessibilityLabel("Unpin \(row.title)")
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(.white.opacity(0.45))
                .help("Drag to change which pin is in front")
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 6)
        .frame(maxHeight: .infinity)
        .background(.white.opacity(hovering || focused ? 0.08 : 0), in: .rect(cornerRadius: 10))
        .contentShape(.rect)
        .onHover { hovering = $0 }
        .onTapGesture { actions.jump(row.id) }
        .focusable()
        .focused($focused)
        .focusEffectDisabled()
        .onKeyPress(.return) {
            actions.jump(row.id)
            return .handled
        }
        // Reordering without dragging: ⌥⌘↑ / ⌥⌘↓ on a focused row.
        .onKeyPress(keys: [.upArrow, .downArrow]) { press in
            guard press.modifiers.contains(.command), press.modifiers.contains(.option) else { return .ignored }
            actions.move(row.id, press.key == .upArrow)
            return .handled
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel([row.title, row.subtitle, row.minimized ? "minimised" : nil].compactMap { $0 }.joined(separator: ", "))
        .accessibilityAction(named: "Jump to Window") { actions.jump(row.id) }
        .accessibilityAction(named: "Move Forward") { if !isFirst { actions.move(row.id, true) } }
        .accessibilityAction(named: "Move Back") { if !isLast { actions.move(row.id, false) } }
    }
}

private struct CandidateRowView: View {
    let candidate: PinManager.Candidate
    let pin: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: pin) {
            HStack(spacing: 10) {
                if let icon = candidate.icon {
                    Image(nsImage: icon).resizable().frame(width: 18, height: 18)
                }
                Text(candidate.title == candidate.appName ? candidate.appName : "\(candidate.appName) – \(candidate.title)")
                    .font(.system(size: 12))
                    .lineLimit(1)
                Spacer()
                if hovering {
                    Image(systemName: "pin.fill").font(.system(size: 11)).foregroundStyle(.tint)
                }
            }
            .padding(.horizontal, 6)
            .frame(height: NotchModel.candidateHeight)
            .background(.white.opacity(hovering ? 0.08 : 0), in: .rect(cornerRadius: 8))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityLabel("Pin \(candidate.appName), \(candidate.title)")
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
