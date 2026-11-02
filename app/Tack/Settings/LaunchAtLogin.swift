import ServiceManagement

/// Wraps the system login item for Tack itself. The system is the source of truth (the user can also
/// switch it off in System Settings › General › Login Items), so nothing is stored by Tack.
@MainActor
@Observable
final class LaunchAtLogin {
    private(set) var status = SMAppService.mainApp.status
    private(set) var lastError: String?

    var isOn: Bool { status == .enabled || status == .requiresApproval }
    var needsApproval: Bool { status == .requiresApproval }

    func refresh() {
        status = SMAppService.mainApp.status
    }

    func set(_ on: Bool) {
        do {
            if on {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            lastError = nil
        } catch {
            lastError = error.localizedDescription
            tackLog("launch at login: \(on ? "register" : "unregister") failed: \(error.localizedDescription)")
        }
        refresh()
        tackLog("launch at login: status \(status.rawValue)")
    }

    func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
