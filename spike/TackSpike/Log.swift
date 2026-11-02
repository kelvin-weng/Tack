import os

private let logger = Logger(subsystem: "studio.kweng.TackSpike", category: "spike")

/// Public so messages are readable with `log show` / Console (NSLog output was redacted).
func spikeLog(_ message: String) {
    logger.notice("\(message, privacy: .public)")
}
