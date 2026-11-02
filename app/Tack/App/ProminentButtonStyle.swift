import SwiftUI

/// Tack's main action button. The system's prominent style draws white text, which is hard to read on the bright
/// teal accent, and doesn't reliably let us change it; black on the accent is about 11:1.
struct ProminentButtonStyle: ButtonStyle {
    @Environment(\.controlSize) private var controlSize
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let large = controlSize == .large || controlSize == .extraLarge
        configuration.label
            .fontWeight(.medium)
            .foregroundStyle(.black)
            .padding(.horizontal, large ? 18 : 14)
            .padding(.vertical, large ? 8 : 5)
            .contentShape(.capsule)
            .glassEffect(.regular.tint(.accentColor).interactive(), in: .capsule)
            .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.5)
    }
}
