import AppKit
import Carbon.HIToolbox

/// The system-wide pin shortcut (F1), customisable in onboarding and Settings. Carbon's RegisterEventHotKey is
/// still the supported way to do this and, unlike a key-event monitor, needs no extra permission.
@MainActor
@Observable
final class HotKey {
    struct Shortcut: Equatable {
        var keyCode: UInt32
        /// Carbon modifier flags (controlKey, optionKey…).
        var modifiers: UInt32
        var display: String
    }

    /// ⌃⌘P rather than ⌃⌥P: ⌃⌥ is VoiceOver's command key, so that combination is swallowed while VoiceOver is on.
    static let defaultShortcut = Shortcut(keyCode: UInt32(kVK_ANSI_P), modifiers: UInt32(controlKey | cmdKey),
                                          display: "⌃⌘P")

    private(set) var shortcut: Shortcut
    private(set) var isRecording = false
    /// Shown under the shortcut, e.g. when another app already uses it.
    private(set) var problem: String?

    @ObservationIgnored private let action: () -> Void
    @ObservationIgnored private var hotKeyRef: EventHotKeyRef?
    @ObservationIgnored private var handlerRef: EventHandlerRef?
    @ObservationIgnored private var recordMonitor: Any?

    init(action: @escaping () -> Void) {
        self.action = action
        shortcut = Self.saved ?? Self.defaultShortcut
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, userData in
            guard let userData else { return noErr }
            let hotKey = Unmanaged<HotKey>.fromOpaque(userData).takeUnretainedValue()
            MainActor.assumeIsolated { hotKey.action() }
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &handlerRef)
        if !register(shortcut) { problem = Self.takenMessage(shortcut) }
    }

    // MARK: Recording a new shortcut

    /// The next key press with ⌘, ⌥ or ⌃ becomes the shortcut; Escape cancels. The current shortcut is switched
    /// off meanwhile so pressing it again doesn't pin something.
    func startRecording() {
        guard !isRecording else { return }
        isRecording = true
        problem = nil
        unregister()
        recordMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            MainActor.assumeIsolated { self?.record(event) }
            return nil
        }
    }

    func stopRecording() {
        guard isRecording else { return }
        if let recordMonitor { NSEvent.removeMonitor(recordMonitor) }
        recordMonitor = nil
        isRecording = false
        if hotKeyRef == nil { register(shortcut) }
    }

    func resetToDefault() {
        stopRecording()
        use(Self.defaultShortcut)
    }

    private func record(_ event: NSEvent) {
        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        if Int(event.keyCode) == kVK_Escape, flags.isEmpty {
            stopRecording()
            return
        }
        guard !flags.isDisjoint(with: [.command, .option, .control]) else {
            problem = "Include ⌘, ⌥ or ⌃ so the shortcut doesn't get in the way of typing."
            NSSound.beep()
            return
        }
        let new = Shortcut(keyCode: UInt32(event.keyCode), modifiers: Self.carbonModifiers(flags),
                           display: Self.symbols(flags) + Self.keyName(event))
        stopRecording()
        use(new)
    }

    private func use(_ new: Shortcut) {
        guard new != shortcut || hotKeyRef == nil else { problem = nil; return }
        unregister()
        if register(new) {
            shortcut = new
            problem = nil
            UserDefaults.standard.set(["keyCode": new.keyCode, "modifiers": new.modifiers, "display": new.display],
                                      forKey: Self.defaultsKey)
        } else {
            problem = Self.takenMessage(new)
            register(shortcut)
        }
    }

    // MARK: Registration

    @discardableResult
    private func register(_ shortcut: Shortcut) -> Bool {
        let id = EventHotKeyID(signature: OSType(0x5441_434B), id: 1) // 'TACK'
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(shortcut.keyCode, shortcut.modifiers, id, GetApplicationEventTarget(), 0, &ref)
        tackLog(status == noErr ? "hotkey: registered \(shortcut.display)"
                                : "hotkey: \(shortcut.display) failed (\(status)), probably taken by another app")
        guard status == noErr else { return false }
        hotKeyRef = ref
        return true
    }

    private func unregister() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        hotKeyRef = nil
    }

    // MARK: Helpers

    private static let defaultsKey = "hotkey"

    private static var saved: Shortcut? {
        guard let dict = UserDefaults.standard.dictionary(forKey: defaultsKey),
              let keyCode = dict["keyCode"] as? UInt32, let modifiers = dict["modifiers"] as? UInt32,
              let display = dict["display"] as? String else { return nil }
        return Shortcut(keyCode: keyCode, modifiers: modifiers, display: display)
    }

    private static func takenMessage(_ shortcut: Shortcut) -> String {
        "\(shortcut.display) is already used by another app. Choose a different shortcut."
    }

    private static func carbonModifiers(_ flags: NSEvent.ModifierFlags) -> UInt32 {
        var result = 0
        if flags.contains(.control) { result |= controlKey }
        if flags.contains(.option) { result |= optionKey }
        if flags.contains(.shift) { result |= shiftKey }
        if flags.contains(.command) { result |= cmdKey }
        return UInt32(result)
    }

    private static func symbols(_ flags: NSEvent.ModifierFlags) -> String {
        (flags.contains(.control) ? "⌃" : "") + (flags.contains(.option) ? "⌥" : "")
            + (flags.contains(.shift) ? "⇧" : "") + (flags.contains(.command) ? "⌘" : "")
    }

    private static let specialKeys: [Int: String] = [
        kVK_Space: "Space", kVK_Return: "↩", kVK_Tab: "⇥", kVK_Delete: "⌫", kVK_ForwardDelete: "⌦",
        kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
        kVK_Home: "↖", kVK_End: "↘", kVK_PageUp: "⇞", kVK_PageDown: "⇟",
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
        kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
    ]

    private static func keyName(_ event: NSEvent) -> String {
        if let name = specialKeys[Int(event.keyCode)] { return name }
        return (event.charactersIgnoringModifiers ?? "?").uppercased()
    }
}
