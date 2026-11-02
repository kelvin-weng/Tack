import os

private let logger = Logger(subsystem: "studio.kweng.Tack", category: "app")

/// Messages are public so they're readable with `log show`; never log window contents or titles here.
func tackLog(_ message: String) {
    logger.notice("\(message, privacy: .public)")
}
