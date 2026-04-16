import Foundation

/// Shells out to the `gws` CLI to interact with Google Workspace.
/// All calls go through the user's existing OAuth scopes — no additional auth needed.
actor GWSService {
    private let gwsPath: String

    init(gwsPath: String = "/usr/local/bin/gws") {
        self.gwsPath = gwsPath
    }

    // MARK: - Gmail

    /// Fetch recent email metadata via `gws gmail +triage --format json`.
    /// Returns parsed Email objects. Uses the +triage helper which fetches
    /// id, from, subject, date in a single efficient call.
    func fetchRecentEmails(maxResults: Int = 50, query: String = "is:unread") async throws -> [Email] {
        let args = [
            "gmail", "+triage",
            "--max", "\(maxResults)",
            "--query", query,
            "--format", "json"
        ]

        let output = try await run(arguments: args)
        return try parseEmails(from: output)
    }

    /// Fetch the full body of a specific email (for deeper triage if needed).
    func fetchEmailBody(messageId: String) async throws -> String {
        let args = [
            "gmail", "+read",
            "--format", "json",
            messageId
        ]
        return try await run(arguments: args)
    }

    // MARK: - Health Check

    /// Verify gws is installed and authenticated.
    func healthCheck() async throws -> Bool {
        let args = ["gmail", "+triage", "--max", "1", "--format", "json"]
        let output = try await run(arguments: args)
        return !output.isEmpty
    }

    // MARK: - Process Execution

    private func run(arguments: [String]) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()

            process.executableURL = URL(fileURLWithPath: gwsPath)
            process.arguments = arguments
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe
            process.environment = ProcessInfo.processInfo.environment

            // Resume continuation asynchronously via terminationHandler (no blocking)
            process.terminationHandler = { _ in
                let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: stdoutData, encoding: .utf8) ?? ""

                if process.terminationStatus != 0 {
                    let errText = String(data: stderrData, encoding: .utf8) ?? output
                    continuation.resume(throwing: GWSError.commandFailed(
                        exitCode: process.terminationStatus,
                        output: errText
                    ))
                } else {
                    continuation.resume(returning: output)
                }
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: GWSError.executionFailed(error))
            }
        }
    }

    // MARK: - Parsing

    /// Parse the JSON output from `gws gmail +triage --format json` into Email structs.
    /// Output format: { "messages": [...], "query": "...", "resultSizeEstimate": N }
    func parseEmails(from jsonString: String) throws -> [Email] {
        // Strip any leading log lines (gws emits "Using keyring backend: keyring" to stdout)
        // Find the first JSON start character — either '{' (object) or '[' (array)
        let objStart = jsonString.firstIndex(of: "{")
        let arrStart = jsonString.firstIndex(of: "[")
        let jsonStart: String.Index
        switch (objStart, arrStart) {
        case (.some(let o), .some(let a)): jsonStart = min(o, a)
        case (.some(let o), nil):          jsonStart = o
        case (nil, .some(let a)):          jsonStart = a
        case (nil, nil):                   jsonStart = jsonString.startIndex
        }
        let cleaned = String(jsonString[jsonStart...])

        guard let data = cleaned.data(using: .utf8) else {
            throw GWSError.invalidOutput
        }

        let decoder = JSONDecoder()

        // +triage returns { "messages": [...], ... }
        struct TriageResponse: Decodable {
            let messages: [Email]
        }

        if let wrapper = try? decoder.decode(TriageResponse.self, from: data) {
            return wrapper.messages
        }
        // Fallback: bare array
        return try decoder.decode([Email].self, from: data)
    }

    // MARK: - Types

    enum GWSError: LocalizedError {
        case invalidOutput
        case commandFailed(exitCode: Int32, output: String)
        case executionFailed(Error)

        var errorDescription: String? {
            switch self {
            case .invalidOutput: "Could not parse gws output"
            case .commandFailed(let code, let out): "gws exited with code \(code): \(out.prefix(200))"
            case .executionFailed(let e): "Failed to execute gws: \(e.localizedDescription)"
            }
        }
    }
}
