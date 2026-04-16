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
            appLog("Starting triage…", level: .info, appState)

            // Step 1: Fetch emails via gws
            appLog("Fetching emails via gws…", level: .info, appState)
            let gwsService = GWSService(gwsPath: appState.gwsPath)
            let emails = try await gwsService.fetchRecentEmails(maxResults: appState.maxEmails)

            guard !emails.isEmpty else {
                appState.lastError = "No emails found in inbox."
                return
            }

            appLog("Fetched \(emails.count) emails", level: .success, appState)
            appState.emails = emails

            // Step 2: Build the prompt
            let emailsJSON = try formatEmailsForPrompt(emails)
            let systemPrompt = Self.triageSystemPrompt
            let userPrompt = appState.triagePromptOverride.isEmpty
                ? Self.triageUserPrompt(emailCount: emails.count, emailsJSON: emailsJSON)
                : appState.triagePromptOverride.replacingOccurrences(of: "{emails_json}", with: emailsJSON)

            // Step 3: Load model if needed, then run inference
            if !appState.engineStatus.isReady {
                appLog("Loading model…", level: .info, appState)
                appState.engineStatus = .loading
                do {
                    try await engine.loadModel(at: appState.modelPath, contextSize: appState.contextSize)
                    appLog("Model loaded", level: .success, appState)
                    appState.engineStatus = .ready
                } catch {
                    appState.engineStatus = .error(error.localizedDescription)
                    appLog(error.localizedDescription, level: .error, appState)
                    throw error
                }
            }

            appLog("Running inference…", level: .info, appState)
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
            appLog("Inference complete", level: .success, appState)

            // Step 4: Parse the structured response
            appLog("Raw model output (\(rawResponse.count) chars): \(rawResponse.prefix(800))", level: .info, appState)
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

            appLog("Triage complete — \(digest.totalEmails) emails ranked", level: .success, appState)

        } catch {
            appState.lastError = error.localizedDescription
            appLog(error.localizedDescription, level: .error, appState)
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

        // Extract from first '{' to last '}'. If the output was truncated and
        // no closing '}' exists, take everything from '{' onward and let the
        // repair step close it.
        if let start = cleaned.firstIndex(of: "{") {
            if let end = cleaned.lastIndex(of: "}") {
                cleaned = String(cleaned[start...end])
            } else {
                cleaned = String(cleaned[start...])
            }
        }

        guard let data = cleaned.data(using: .utf8) else {
            throw TriageError.invalidJSON("Could not convert model output to data")
        }

        // First attempt: parse as-is
        if let result = try? JSONDecoder().decode(TriageResult.self, from: data) {
            return result
        }

        // Second attempt: repair truncated JSON by closing unclosed structures
        let repaired = Self.repairTruncatedJSON(cleaned)
        appLog("Attempting JSON repair — original \(cleaned.count) chars, repaired \(repaired.count) chars", level: .warning, appState)
        if let repairedData = repaired.data(using: .utf8),
           let result = try? JSONDecoder().decode(TriageResult.self, from: repairedData) {
            appLog("JSON repair succeeded", level: .success, appState)
            return result
        }

        // Both attempts failed — surface a useful error
        let detail = describeJSONError(cleaned)
        throw TriageError.parseFailed("Parse failed [\(detail)] — raw: \(cleaned.prefix(1000))")
    }

    /// Close unclosed brackets/braces so a truncated JSON object can be decoded.
    /// Walks the string tracking structural characters while respecting strings and escapes.
    nonisolated static func repairTruncatedJSON(_ json: String) -> String {
        var stack: [Character] = []
        var inString = false
        var escaped = false

        for ch in json {
            if escaped { escaped = false; continue }
            if ch == "\\" && inString { escaped = true; continue }
            if ch == "\"" { inString.toggle(); continue }
            if inString { continue }
            switch ch {
            case "{": stack.append("}")
            case "[": stack.append("]")
            case "}", "]": if stack.last == ch { stack.removeLast() }
            default: break
            }
        }

        var result = json
        if inString { result += "\"" }           // close an open string value
        result += String(stack.reversed())        // close all open objects/arrays
        return result
    }

    private func describeJSONError(_ json: String) -> String {
        guard let data = json.data(using: .utf8) else { return "not UTF-8" }
        do {
            _ = try JSONDecoder().decode(TriageResult.self, from: data)
            return "no error"
        } catch let e as DecodingError {
            switch e {
            case .keyNotFound(let k, _):   return "Missing key '\(k.stringValue)'"
            case .typeMismatch(_, let c):  return "Type mismatch at \(c.codingPath.map(\.stringValue).joined(separator: "."))"
            case .valueNotFound(_, let c): return "Null at \(c.codingPath.map(\.stringValue).joined(separator: "."))"
            case .dataCorrupted(let c):    return "Corrupted: \(c.debugDescription)"
            @unknown default:             return e.localizedDescription
            }
        } catch {
            return error.localizedDescription
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
