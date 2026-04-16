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

        if let start = cleaned.firstIndex(of: "{") {
            if let end = cleaned.lastIndex(of: "}") {
                cleaned = String(cleaned[start...end])
            } else {
                cleaned = String(cleaned[start...])
            }
        }

        guard let data = cleaned.data(using: .utf8) else {
            throw EmailTriageService.TriageError.invalidJSON("Could not convert to data")
        }

        // First attempt: as-is
        if let result = try? JSONDecoder().decode(TriageResult.self, from: data) {
            return result
        }

        // Second attempt: repair truncated JSON
        let repaired = EmailTriageService.repairTruncatedJSON(cleaned)
        if let repairedData = repaired.data(using: .utf8),
           let result = try? JSONDecoder().decode(TriageResult.self, from: repairedData) {
            return result
        }

        throw EmailTriageService.TriageError.parseFailed("Parse failed — raw: \(cleaned.prefix(500))")
    }
}
