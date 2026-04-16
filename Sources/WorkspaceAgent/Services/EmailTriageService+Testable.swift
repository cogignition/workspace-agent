import Foundation

/// Test-visible wrappers for private EmailTriageService methods.
/// Only used in unit tests — not exposed in the public API.
extension EmailTriageService {
    nonisolated static func testParseTriageResult(_ rawJSON: String) throws -> TriageResult {
        // Replicates the private parseTriageResult logic for testing
        var cleaned = rawJSON
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if let start = cleaned.firstIndex(of: "{"),
           let end = cleaned.lastIndex(of: "}") {
            cleaned = String(cleaned[start...end])
        }

        guard let data = cleaned.data(using: .utf8) else {
            throw EmailTriageService.TriageError.invalidJSON("Could not convert to data")
        }

        do {
            return try JSONDecoder().decode(TriageResult.self, from: data)
        } catch {
            throw EmailTriageService.TriageError.parseFailed("Parse failed: \(error.localizedDescription)")
        }
    }
}
