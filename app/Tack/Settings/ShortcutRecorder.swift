import SwiftUI

/// Shows the pin shortcut; click it, then press a new one. Used in Settings and onboarding.
struct ShortcutRecorder: View {
    let hotKey: HotKey

    var body: some View {
        VStack(alignment: .trailing, spacing: 6) {
            HStack(spacing: 8) {
                Button {
                    hotKey.isRecording ? hotKey.stopRecording() : hotKey.startRecording()
                } label: {
                    Text(hotKey.isRecording ? "Type a shortcut…" : hotKey.shortcut.display)
                        .font(.body.monospaced())
                        .frame(minWidth: 120)
                }
                .help(hotKey.isRecording ? "Press the new shortcut, or Escape to cancel" : "Click to change")
                .accessibilityLabel(hotKey.isRecording ? "Recording. Press the new shortcut, or Escape to cancel"
                                                       : "Pin shortcut, \(hotKey.shortcut.display)")
                .accessibilityHint(hotKey.isRecording ? "" : "Changes the shortcut")
                if hotKey.shortcut != HotKey.defaultShortcut, !hotKey.isRecording {
                    Button("Reset") { hotKey.resetToDefault() }
                        .accessibilityLabel("Reset to \(HotKey.defaultShortcut.display)")
                }
            }
            if let problem = hotKey.problem {
                Text(problem)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.trailing)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onDisappear { hotKey.stopRecording() }
    }
}
