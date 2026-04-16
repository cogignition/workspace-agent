import SwiftUI
import Observation

/// Central observable state for the app. Shared across MenuBarExtra, digest panel, and settings.
@Observable
final class AppState {
    // MARK: - Services (long-lived, wired at init)
    private(set) var inferenceEngine: InferenceEngine!
    private(set) var triageService: EmailTriageService!

    // MARK: - Inference Engine
    var engineStatus: EngineStatus = .idle
    var modelName: String = "gemma-4-12b"

    // MARK: - Email Triage
    var emails: [Email] = []
    var digest: EmailDigest?
    var isTriaging: Bool = false
    var lastTriageDate: Date?

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

        // Wire up long-lived services
        let engine = InferenceEngine()
        self.inferenceEngine = engine
        self.triageService = EmailTriageService(appState: self, engine: engine)
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
