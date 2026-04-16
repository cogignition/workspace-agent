import Foundation

/// Shells out to the `gws` CLI to interact with Google Workspace.
/// All calls go through the user's existing OAuth scopes — no additional auth needed.
actor GWSService {
    private let gwsPath: String

    init(gwsPath: String = "/usr/local/bin/gws") {
        self.gwsPath = gwsPath
    }

    // MARK: - Gmail

    /// Fetch recent email metadata via `gws gmail messages list`.
    /// Returns parsed Email objects from the JSON output.
    func fetchRecentEmails(maxResults: Int = 50, query: String = "is:inbox") async throws -> [Email] {
        let args = [
            "gmail", "messages", "list",
            "--format", "json",
            "--max-results", "\(maxResults)",
            "--query", query
        ]

        let output = try await run(arguments: args)
        let emails = try parseEmails(from: output)
        return emails
    }

    /// Fetch the full body of a specific email (for deeper triage if needed).
    func fetchEmailBody(messageId: String) async throws -> String {
        let args = [
            "gmail", "messages", "get",
            "--format", "json",
            "--message-id", messageId
        ]

        return try await run(arguments: args)
    }

    // MARK: - Health Check

    /// Verify gws is installed and authenticated.
    func healthCheck() async throws -> Bool {
        let args = ["version"]
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
                } else if output.isEmpty && stdoutData.isEmpty {
                    continuation.resume(throwing: GWSError.invalidOutput)
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

    /// Parse the JSON output from `gws gmail messages list` into Email structs.
    /// The gws CLI outputs a JSON array of message metadata.
    private func parseEmails(from jsonString: String) throws -> [Email] {
        guard let data = jsonString.data(using: .utf8) else {
            throw GWSError.invalidOutput
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let dateString = try container.decode(String.self)

            // gws outputs RFC 3339 dates
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: dateString) {
                return date
            }
            // Fallback: try without fractional seconds
            formatter.formatOptions = [.withInternetDateTime]
            if let date = formatter.date(from: dateString) {
                return date
            }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Cannot decode date: \(dateString)"
            )
        }

        // gws may return { "messages": [...] } or a bare array depending on version
        if let wrapper = try? decoder.decode(GWSMessageListResponse.self, from: data) {
            return wrapper.messages
        }
        return try decoder.decode([Email].self, from: data)
    }

    // MARK: - Types

    private struct GWSMessageListResponse: Codable {
        let messages: [Email]
    }

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
