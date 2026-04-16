import Foundation
import OSLog

let logger = Logger(subsystem: "com.openlane.workspace-agent", category: "triage")

/// Log to both os_log and the in-app buffer.
@MainActor
func appLog(_ message: String, level: LogLevel = .info, _ appState: AppState) {
    // Log to os_log
    logger.log(level: osLogLevel(level), "\(message)")

    // Log to in-app buffer
    appState.log(message, level: level)
}

private func osLogLevel(_ level: LogLevel) -> OSLogType {
    switch level {
    case .info: .info
    case .success: .info
    case .warning: .debug
    case .error: .error
    }
}
