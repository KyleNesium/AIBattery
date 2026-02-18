import os

/// Structured logging for AIBattery — replaces bare `print()` calls.
/// View logs in Console.app by filtering for subsystem "com.KyleNesium.AIBattery".
enum AppLogger {
    static let general = Logger(subsystem: "com.KyleNesium.AIBattery", category: "general")
    static let oauth = Logger(subsystem: "com.KyleNesium.AIBattery", category: "oauth")
    static let network = Logger(subsystem: "com.KyleNesium.AIBattery", category: "network")
    static let files = Logger(subsystem: "com.KyleNesium.AIBattery", category: "files")
}
