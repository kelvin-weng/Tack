import AppKit
import ApplicationServices

// Private but long-stable API; the only reliable way to match an AX window to a CGWindowID.
@_silgen_name("_AXUIElementGetWindow")
private func _AXUIElementGetWindow(_ element: AXUIElement, _ id: UnsafeMutablePointer<CGWindowID>) -> AXError

/// A real window in another app, controlled through the Accessibility API. Frames are CG (top-left origin).
@MainActor
final class AXWindow {
    enum Event {
        case movedOrResized, focusedWindowChanged, minimized, deminimized, destroyed
    }

    let pid: pid_t
    let windowID: CGWindowID
    private let app: AXUIElement
    private let element: AXUIElement
    private var observer: AXObserver?

    var onEvent: ((Event) -> Void)?

    /// The focused window of the frontmost app, i.e. what the user means by "this window".
    static func frontmost() -> AXWindow? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        let window = value as! AXUIElement
        var id: CGWindowID = 0
        guard _AXUIElementGetWindow(window, &id) == .success else { return nil }
        return AXWindow(pid: app.processIdentifier, windowID: id, app: appElement, element: window)
    }

    static func find(windowID: CGWindowID, pid: pid_t) -> AXWindow? {
        let app = AXUIElementCreateApplication(pid)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value) == .success,
              let windows = value as? [AXUIElement] else { return nil }
        for window in windows {
            var id: CGWindowID = 0
            if _AXUIElementGetWindow(window, &id) == .success, id == windowID {
                return AXWindow(pid: pid, windowID: id, app: app, element: window)
            }
        }
        return nil
    }

    private init(pid: pid_t, windowID: CGWindowID, app: AXUIElement, element: AXUIElement) {
        self.pid = pid
        self.windowID = windowID
        self.app = app
        self.element = element
    }

    var frame: CGRect? {
        var posValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &posValue) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue) == .success
        else { return nil }
        var point = CGPoint.zero
        var size = CGSize.zero
        AXValueGetValue(posValue as! AXValue, .cgPoint, &point)
        AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
        return CGRect(origin: point, size: size)
    }

    /// One IPC call; used on every mouse move while dragging.
    func setPosition(_ point: CGPoint) {
        var point = point
        AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, AXValueCreate(.cgPoint, &point)!)
    }

    func setFrame(_ rect: CGRect) {
        var point = rect.origin
        var size = rect.size
        // Size, position, size: some apps clamp size against the old position.
        AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, AXValueCreate(.cgSize, &size)!)
        AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, AXValueCreate(.cgPoint, &point)!)
        AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, AXValueCreate(.cgSize, &size)!)
    }

    var isMinimized: Bool {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXMinimizedAttribute as CFString, &value) == .success else { return false }
        return (value as? Bool) ?? false
    }

    func deminimize() {
        AXUIElementSetAttributeValue(element, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
    }

    /// Brings the app forward and this window to its front. Uses AX rather than NSRunningApplication.activate(),
    /// because macOS often refuses activation requests from an app that isn't itself active.
    func raise() {
        AXUIElementSetAttributeValue(app, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
        AXUIElementSetAttributeValue(element, kAXMainAttribute as CFString, kCFBooleanTrue)
        AXUIElementPerformAction(element, kAXRaiseAction as CFString)
    }

    var isFocusedWindow: Bool {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &value) == .success,
              let value else { return false }
        return CFEqual(value, element)
    }

    func startObserving() {
        guard observer == nil else { return }
        var observer: AXObserver?
        let result = AXObserverCreate(pid, { _, _, notification, refcon in
            guard let refcon else { return }
            let window = Unmanaged<AXWindow>.fromOpaque(refcon).takeUnretainedValue()
            let name = notification as String
            MainActor.assumeIsolated { window.handle(name) }
        }, &observer)
        guard result == .success, let observer else {
            tackLog("ax: observer create failed (\(result.rawValue))")
            return
        }
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        for name in [kAXMovedNotification, kAXResizedNotification, kAXUIElementDestroyedNotification,
                     kAXWindowMiniaturizedNotification, kAXWindowDeminiaturizedNotification] {
            AXObserverAddNotification(observer, element, name as CFString, refcon)
        }
        AXObserverAddNotification(observer, app, kAXFocusedWindowChangedNotification as CFString, refcon)
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        self.observer = observer
    }

    func stopObserving() {
        guard let observer else { return }
        CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        self.observer = nil
    }

    private func handle(_ name: String) {
        switch name {
        case kAXMovedNotification, kAXResizedNotification: onEvent?(.movedOrResized)
        case kAXFocusedWindowChangedNotification: onEvent?(.focusedWindowChanged)
        case kAXWindowMiniaturizedNotification: onEvent?(.minimized)
        case kAXWindowDeminiaturizedNotification: onEvent?(.deminimized)
        case kAXUIElementDestroyedNotification: onEvent?(.destroyed)
        default: break
        }
    }
}
