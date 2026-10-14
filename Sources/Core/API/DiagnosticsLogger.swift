import os

/// Trimmed from kaset `Utilities/DiagnosticsLogger.swift`: only the categories the iOS app uses.
enum DiagnosticsLogger {
    static let auth = Logger(subsystem: "dev.emoona.kaset", category: "Auth")
    static let api = Logger(subsystem: "dev.emoona.kaset", category: "API")
    static let player = Logger(subsystem: "dev.emoona.kaset", category: "Player")
    static let ui = Logger(subsystem: "dev.emoona.kaset", category: "UI")
}
