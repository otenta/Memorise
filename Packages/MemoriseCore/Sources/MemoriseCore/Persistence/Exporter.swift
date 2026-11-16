import Foundation

/// Serialises stored data for the user (JSON of everything, CSV of attempts).
public enum Exporter {
    public static func json(_ snapshot: ExportSnapshot) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(snapshot)
    }

    public static let csvHeader = "session_id,deck_id,index,item_key,shown_at,response_ms,grade_ms,correct,is_retry,was_interrupted"

    /// RFC 4180 CSV of attempts (CRLF line endings).
    public static func csv(_ attempts: [Attempt]) -> String {
        let iso = ISO8601DateFormatter()
        var out = csvHeader
        out.reserveCapacity(attempts.count * 128)
        for a in attempts {
            out += "\r\n"
            out += [
                a.sessionID.uuidString, escape(a.deckID.raw), String(a.index), escape(a.itemKey.raw),
                iso.string(from: a.shownAt), String(a.responseMs), String(a.gradeMs),
                a.correct ? "1" : "0", a.isRetry ? "1" : "0", a.wasInterrupted ? "1" : "0",
            ].joined(separator: ",")
        }
        out += "\r\n"
        return out
    }

    /// Quotes a field if it contains a comma, quote or newline; doubles inner quotes.
    public static func escape(_ field: String) -> String {
        guard field.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" }) else { return field }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
