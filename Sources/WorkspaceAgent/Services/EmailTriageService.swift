import Foundation

/// Orchestrates the email triage pipeline:
///   1. Fetch emails via gws CLI
///   2. Format as JSON for the model
///   3. Run Gemma 4 inference to rank and summarize
///   4. Parse structured output into an EmailDigest
///
/// This is the core "intent → structured action" loop.
/// Long-lived — created once at app launch and stored on AppState.
@MainActor
final class EmailTriageService {
    private let appState: AppState
    private let engine: InferenceEngine

    init(appState: AppState, engine: InferenceEngine) {
        self.appState = appState
        self.engine = engine
    }

    /// Run the full triage pipeline.
    func runTriage() async {
        guard !appState.isTriaging else { return }
        appState.isTriaging = true
        appState.lastError = nil

        defer { appState.isTriaging = false }

        // Guard: model path must be configured
        guard !appState.modelPath.isEmpty else {
            appState.lastError = "Set a model path in Settings first."
            return
        }

        do {
            // Step 1: Fetch emails via gws
            let gwsService = GWSService(gwsPath: appState.gwsPath)
            let emails = try await gwsService.fetchRecentEmails(maxResults: appState.maxEmails)

            guard !emails.isEmpty else {
                appState.lastError = "No emails found in inbox."
                return
            }

            appState.emails = emails

            // Step 2: Build the prompt
            let emailsJSON = try formatEmailsForPrompt(emails)
            let systemPrompt = Self.triageSystemPrompt
            let userPrompt = appState.triagePromptOverride.isEmpty
                ? Self.triageUserPrompt(emailCount: emails.count, emailsJSON: emailsJSON)
                : appState.triagePromptOverride.replacingOccurrences(of: "{emails_json}", with: emailsJSON)

            // Step 3: Load model if needed, then run inference
            if !appState.engineStatus.isReady {
                appState.engineStatus = .loading
                do {
                    try await engine.loadModel(at: appState.modelPath)
                    appState.engineStatus = .ready
                } catch {
                    appState.engineStatus = .error(error.localizedDescription)
                    throw error
                }
            }

            appState.engineStatus = .generating(progress: "Starting…")
            let timeout = appState.modelUnloadTimeout

            let rawResponse = try await engine.generate(
                systemPrompt: systemPrompt,
                userPrompt: userPrompt,
                unloadTimeout: timeout,
                onProgress: { [weak self] tokenCount in
                    await MainActor.run {
                        self?.appState.engineStatus = .generating(progress: "Generated \(tokenCount) tokens…")
                    }
                }
            )

            // Update status based on whether model will stay loaded
            appState.engineStatus = timeout > 0 ? .ready : .idle

            // Step 4: Parse the structured response
            let triageResult = try parseTriageResult(rawResponse)

            // Step 5: Merge triage results back into emails and build digest
            var rankedEmails = emails
            for triaged in triageResult.rankedEmails {
                if let idx = rankedEmails.firstIndex(where: { $0.id == triaged.emailId }) {
                    rankedEmails[idx].priority = triaged.priority
                    rankedEmails[idx].triageReason = triaged.reason
                }
            }
            rankedEmails.sort { ($0.priority ?? 99) < ($1.priority ?? 99) }

            let digest = EmailDigest(
                generatedAt: Date(),
                totalEmails: emails.count,
                rankedEmails: rankedEmails,
                summary: triageResult.summary
            )

            appState.digest = digest
            appState.lastTriageDate = Date()

        } catch {
            appState.lastError = error.localizedDescription
        }
    }

    // MARK: - Prompt Engineering

    /// System prompt: instructs Gemma 4 to act as an email triage assistant
    /// producing structured JSON output.
    static let triageSystemPrompt = """
    You are an email triage assistant for a busy professional. Your job is to analyze \
    a batch of emails and produce a structured ranking.

    You MUST respond with valid JSON matching this exact schema:
    {
      "rankedEmails": [
        {
          "emailId": "string",
          "priority": 1-5,
          "reason": "one sentence explaining why",
          "suggestedAction": "reply_now" | "review_today" | "delegate" | "archive" | "fyi"
        }
      ],
      "summary": "2-3 sentence overview of the inbox state"
    }

    Priority scale:
    1 = Urgent — needs a reply within the hour (from leadership, blocking issues, time-sensitive)
    2 = Important — should be handled today (direct requests, project updates needing input)
    3 = Normal — useful to read but no action required today
    4 = Low — newsletters, automated notifications, FYI threads
    5 = Noise — marketing, spam that passed filters, irrelevant cc's

    Rules:
    - Rank ALL emails provided — do not skip any
    - Be concise in reasons — one sentence max
    - Consider sender seniority, time sensitivity, and whether a response is expected
    - When in doubt, rank higher rather than lower
    - Output ONLY the JSON object, no markdown fences, no commentary
    """

    /// User prompt with the email batch injected.
    static func triageUserPrompt(emailCount: Int, emailsJSON: String) -> String {
        """
        Triage the following \(emailCount) emails from my inbox. \
        Rank them by priority and suggest an action for each.

        Emails:
        \(emailsJSON)
        """
    }

    // MARK: - Helpers

    /// Format emails as compact JSON for the prompt, keeping only fields the model needs.
    private func formatEmailsForPrompt(_ emails: [Email]) throws -> String {
        struct PromptEmail: Codable {
            let id: String
            let from: String
            let subject: String
            let date: String
            let isUnread: Bool
        }

        let promptEmails = emails.map { email in
            PromptEmail(
                id: email.id,
                from: email.from,
                subject: email.subject,
                date: email.date,
                isUnread: email.isUnread
            )
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(promptEmails)
        return String(data: data, encoding: .utf8) ?? "[]"
    }

    /// Parse the model's JSON response into a TriageResult.
    private func parseTriageResult(_ rawJSON: String) throws -> TriageResult {
        // Clean up: model might wrap in markdown fences despite instructions
        var cleaned = rawJSON
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // Find the JSON object boundaries if there's surrounding text
        if let start = cleaned.firstIndex(of: "{"),
           let end = cleaned.lastIndex(of: "}") {
            cleaned = String(cleaned[start...end])
        }

        guard let data = cleaned.data(using: .utf8) else {
            throw TriageError.invalidJSON("Could not convert model output to data")
        }

        do {
            return try JSONDecoder().decode(TriageResult.self, from: data)
        } catch {
            throw TriageError.parseFailed(
                "Failed to parse triage result: \(error.localizedDescription)\nRaw output: \(rawJSON.prefix(500))"
            )
        }
    }

    enum TriageError: LocalizedError {
        case invalidJSON(String)
        case parseFailed(String)

        var errorDescription: String? {
            switch self {
            case .invalidJSON(let msg): msg
            case .parseFailed(let msg): msg
            }
        }
    }
}
