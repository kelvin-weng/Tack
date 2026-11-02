import AppKit
import SwiftUI

/// Follows System Settings › Accessibility › Display › Reduce motion: springs and slides become short fades.
@MainActor
enum Motion {
    static var reduced: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    static func spring(duration: Double, bounce: Double = 0) -> Animation {
        reduced ? .easeInOut(duration: 0.15) : .spring(duration: duration, bounce: bounce)
    }
}
