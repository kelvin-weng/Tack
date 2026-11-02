import SwiftUI

enum Onboarding {
    enum Step: Int, CaseIterable {
        case welcome, screenRecording, accessibility, shortcut, done
    }

    private static let welcomedKey = "onboarding.welcomed"
    private static let completedKey = "onboarding.completed"
    private static let shortcutSeenKey = "onboarding.shortcutSeen"

    static var welcomed: Bool {
        get { UserDefaults.standard.bool(forKey: welcomedKey) }
        set { UserDefaults.standard.set(newValue, forKey: welcomedKey) }
    }

    static var shortcutSeen: Bool {
        get { UserDefaults.standard.bool(forKey: shortcutSeenKey) }
        set { UserDefaults.standard.set(newValue, forKey: shortcutSeenKey) }
    }

    static var completed: Bool {
        get { UserDefaults.standard.bool(forKey: completedKey) }
        set { UserDefaults.standard.set(newValue, forKey: completedKey) }
    }

    @MainActor
    static func needsToShow(permissions: Permissions) -> Bool {
        !completed || !permissions.allGranted
    }

    /// Where to (re)start, e.g. after macOS made Tack quit and reopen mid-way.
    @MainActor
    static func firstIncompleteStep(permissions: Permissions) -> Step {
        if !welcomed { return .welcome }
        if !permissions.screenRecording { return .screenRecording }
        if !permissions.accessibility { return .accessibility }
        if !shortcutSeen { return .shortcut }
        return .done
    }
}

struct OnboardingView: View {
    let permissions: Permissions
    let hotKey: HotKey
    let finish: () -> Void
    @State private var step: Onboarding.Step

    init(permissions: Permissions, hotKey: HotKey, finish: @escaping () -> Void) {
        self.permissions = permissions
        self.hotKey = hotKey
        self.finish = finish
        _step = State(initialValue: Onboarding.firstIncompleteStep(permissions: permissions))
    }

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch step {
                case .welcome: welcome
                case .screenRecording: screenRecording
                case .accessibility: accessibility
                case .shortcut: shortcut
                case .done: done
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .transition(Motion.reduced ? .opacity
                        : .asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                      removal: .move(edge: .leading).combined(with: .opacity)))
            .id(step)

            StepDots(current: step)
                .padding(.bottom, 20)
        }
        .padding(.horizontal, 40)
        .padding(.top, 28)
        .frame(width: 500, height: 440)
        .onChange(of: permissions.screenRecording) { _, granted in
            if granted, step == .screenRecording { advance(after: 0.8) }
        }
        .onChange(of: permissions.accessibility) { _, granted in
            if granted, step == .accessibility { advance(after: 0.8) }
        }
    }

    // MARK: Steps

    private var welcome: some View {
        StepLayout(symbol: nil,
                   title: "Welcome to Tack",
                   message: "Keep any window on top – a video call, your music, your notes – while you work in everything else. Tack lives in your notch and menu bar.") {
            Button("Get Started") {
                Onboarding.welcomed = true
                advance()
            }
            .buttonStyle(ProminentButtonStyle())
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
        }
    }

    private var screenRecording: some View {
        PermissionStep(
            symbol: "rectangle.on.rectangle",
            title: "Let Tack see your windows",
            message: "Tack needs to see your windows to float them. Nothing is recorded or saved, and nothing leaves your Mac.",
            instruction: "Click Open System Settings and turn on Tack. macOS then offers to quit and reopen Tack: choose Quit & Reopen and this window comes straight back.",
            granted: permissions.screenRecording,
            request: { permissions.request(.screenRecording) },
            restartHint: "Turned it on but still waiting? Restart Tack to finish.",
            relaunch: { permissions.relaunch() }
        )
        .onAppear { permissions.startWatching() }
    }

    private var accessibility: some View {
        PermissionStep(
            symbol: "cursorarrow.click.2",
            title: "Let Tack move your windows",
            message: "When you click a pinned window, Tack brings the real one forward in the same spot so you can use it as normal. That needs Accessibility access.",
            instruction: "Click Open System Settings and turn on Tack.",
            granted: permissions.accessibility,
            request: { permissions.request(.accessibility) },
            restartHint: nil,
            relaunch: nil
        )
        .onAppear { permissions.startWatching() }
    }

    private var shortcut: some View {
        StepLayout(symbol: "keyboard",
                   title: "Your pin shortcut",
                   message: "Press it in any window to keep that window on top. Press it again to unpin. Click the shortcut below to choose a different one.") {
            VStack(spacing: 16) {
                ShortcutRecorder(hotKey: hotKey)
                    .controlSize(.large)
                Button("Continue") {
                    hotKey.stopRecording()
                    Onboarding.shortcutSeen = true
                    advance()
                }
                .buttonStyle(ProminentButtonStyle())
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
                .disabled(hotKey.isRecording)
            }
        }
    }

    private var done: some View {
        StepLayout(symbol: "checkmark.circle.fill",
                   title: "You're all set",
                   message: "Hover over the notch or click the pin in the menu bar to see your pins. Settings are in the menu bar too.") {
            Button("Done") {
                Onboarding.completed = true
                permissions.stopWatching()
                finish()
            }
            .buttonStyle(ProminentButtonStyle())
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
        }
        .onAppear { permissions.stopWatching() }
    }

    private func advance(after delay: Double = 0) {
        let next = Onboarding.firstIncompleteStep(permissions: permissions)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            withAnimation(Motion.reduced ? .easeInOut(duration: 0.15) : .smooth(duration: 0.35)) { step = next }
        }
    }
}

private struct StepLayout<Actions: View>: View {
    /// nil shows the app icon (welcome step).
    let symbol: String?
    let title: String
    let message: String
    @ViewBuilder let actions: Actions

    var body: some View {
        VStack(spacing: 16) {
            Spacer(minLength: 0)
            Group {
                if let symbol {
                    Image(systemName: symbol)
                        .font(.system(size: 52, weight: .medium))
                        .foregroundStyle(.tint)
                        .frame(width: 96, height: 96)
                        .glassEffect(.regular, in: .circle)
                } else {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 112, height: 112)
                }
            }
            .accessibilityHidden(true)
            Text(title)
                .font(.title.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
            Text(message)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            actions
            Spacer(minLength: 0)
        }
    }
}

private struct PermissionStep: View {
    let symbol: String
    let title: String
    let message: String
    let instruction: String
    let granted: Bool
    let request: () -> Void
    let restartHint: String?
    let relaunch: (() -> Void)?
    @State private var asked = false

    var body: some View {
        StepLayout(symbol: symbol, title: title, message: message) {
            VStack(spacing: 12) {
                if granted {
                    Label("Done – thanks!", systemImage: "checkmark.circle.fill")
                        .font(.headline)
                        .foregroundStyle(.green)
                } else {
                    Text(instruction)
                        .font(.callout)
                    Button("Open System Settings") {
                        asked = true
                        request()
                    }
                    .buttonStyle(ProminentButtonStyle())
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)
                    if asked {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text("Waiting for you to turn it on…")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                        if let restartHint, let relaunch {
                            VStack(spacing: 6) {
                                Text(restartHint)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.center)
                                Button("Restart Tack", action: relaunch)
                                    .buttonStyle(.glass)
                            }
                            .padding(.top, 4)
                        }
                    }
                }
            }
            .frame(minHeight: 140, alignment: .top)
        }
    }
}

private struct StepDots: View {
    let current: Onboarding.Step

    var body: some View {
        HStack(spacing: 8) {
            ForEach(Onboarding.Step.allCases, id: \.self) { step in
                Circle()
                    .fill(step == current ? AnyShapeStyle(.tint) : AnyShapeStyle(.quaternary))
                    .frame(width: 7, height: 7)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Step \(current.rawValue + 1) of \(Onboarding.Step.allCases.count)")
    }
}
