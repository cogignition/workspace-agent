import SwiftUI
import Observation
import OSLog

/// Central observable state for the app. Shared across MenuBarExtra, digest panel, and settings.
@Observable
final class AppState {
    // MARK: - Services (long-lived, wired at init)
    private(set) var inferenceEngine: InferenceEngine!
    private(set) var triageService: EmailTriageService!

    // MARK: - Inference Engine
    var engineStatus: EngineStatus = .idle

    /// Derived from modelPath — shows just the filename in the menu bar footer.
    var modelName: String {
        let name = URL(fileURLWithPath: modelPath).deletingPathExtension().lastPathComponent
        return name.isEmpty ? "No model set" : name
    }

    // MARK: - Email Triage
    var emails: [Email] = []
    var digest: EmailDigest?
    var isTriaging: Bool = false
    var lastTriageDate: Date?

    // MARK: - Activity Log
    var logEntries: [LogEntry] = []
    private let maxLogEntries = 200

    // MARK: - Settings
    var gwsPath: String = "/usr/local/bin/gws" {
        didSet { UserDefaults.standard.set(gwsPath, forKey: "gwsPath") }
    }
    var modelPath: String = "" {
        didSet { UserDefaults.standard.set(modelPath, forKey: "modelPath") }
    }
    var maxEmails: Int = 50 {
        didSet { UserDefaults.standard.set(maxEmails, forKey: "maxEmails") }
    }
    var triagePromptOverride: String = "" {
        didSet { UserDefaults.standard.set(triagePromptOverride, forKey: "triagePromptOverride") }
    }
    /// How long (seconds) to keep the model in memory after triage. 0 = unload immediately.
    var modelUnloadTimeout: TimeInterval = 300 {
        didSet { UserDefaults.standard.set(modelUnloadTimeout, forKey: "modelUnloadTimeout") }
    }
    /// Context window size (tokens) passed to llama.cpp at model load.
    /// Larger values allow longer email batches but use proportionally more RAM.
    /// Gemma 3 supports up to 128K; practical range for email triage: 4096–32768.
    var contextSize: Int = 8192 {
        didSet { UserDefaults.standard.set(contextSize, forKey: "contextSize") }
    }

    // MARK: - Errors
    var lastError: String?

    // MARK: - Init

    @MainActor init() {
        // Restore persisted settings
        let defaults = UserDefaults.standard
        if let path = defaults.string(forKey: "gwsPath"), !path.isEmpty {
            gwsPath = path
        }
        if let path = defaults.string(forKey: "modelPath") {
            modelPath = path
        }
        if defaults.object(forKey: "maxEmails") != nil {
            maxEmails = defaults.integer(forKey: "maxEmails")
        }
        if let prompt = defaults.string(forKey: "triagePromptOverride") {
            triagePromptOverride = prompt
        }
        if defaults.object(forKey: "modelUnloadTimeout") != nil {
            modelUnloadTimeout = defaults.double(forKey: "modelUnloadTimeout")
        }
        if defaults.object(forKey: "contextSize") != nil {
            contextSize = defaults.integer(forKey: "contextSize")
        }

        // Wire up long-lived services
        let engine = InferenceEngine()
        self.inferenceEngine = engine
        self.triageService = EmailTriageService(appState: self, engine: engine)
    }

    // MARK: - Logging

    @MainActor
    func log(_ message: String, level: LogLevel = .info) {
        let entry = LogEntry(date: Date(), level: level, message: message)
        logEntries.append(entry)

        // Keep buffer capped at maxLogEntries, drop oldest
        if logEntries.count > maxLogEntries {
            logEntries.removeFirst(logEntries.count - maxLogEntries)
        }
    }

    // MARK: - Engine Status

    enum EngineStatus: Equatable {
        case idle
        case loading
        case ready
        case generating(progress: String)
        case error(String)

        var isReady: Bool {
            if case .ready = self { return true }
            return false
        }
    }
}

// MARK: - Log Entry

struct LogEntry: Identifiable, Sendable {
    let id: UUID = UUID()
    let date: Date
    let level: LogLevel
    let message: String
}

enum LogLevel: String, Sendable {
    case info = "info"
    case success = "success"
    case warning = "warning"
    case error = "error"
}
