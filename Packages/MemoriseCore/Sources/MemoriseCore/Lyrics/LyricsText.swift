import Foundation

/// Text clean-up shared by the lyrics parsers.
public enum LyricsText {
    /// Splits raw lyrics into display lines: trimmed, runs of blank lines collapsed to one empty line,
    /// leading/trailing blanks dropped, `[Chorus]`-style lines flagged as section headers.
    /// A blank line is `LyricLine(text: "")`.
    public static func lines(from raw: String) -> [LyricLine] {
        var out: [LyricLine] = []
        for piece in raw.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline) {
            let text = piece.trimmingCharacters(in: .whitespaces)
            if text.isEmpty {
                if let last = out.last, !last.text.isEmpty { out.append(LyricLine(text: "")) }
            } else {
                out.append(LyricLine(text: text, isSectionHeader: isSectionHeader(text)))
            }
        }
        while let last = out.last, last.text.isEmpty { out.removeLast() }
        return out
    }

    /// `[Chorus]`, `[Verse 1: Jungkook]`.
    public static func isSectionHeader(_ text: String) -> Bool {
        text.hasPrefix("[") && text.hasSuffix("]")
    }

    /// Decodes the HTML entities lyrics pages use: named (`&amp; &quot; &lt; &gt; &apos; &nbsp;`), `&#NNN;` and `&#xHH;`.
    public static func decodeHTMLEntities(_ text: String) -> String {
        guard text.contains("&") else { return text }
        let named = ["amp": "&", "quot": "\"", "lt": "<", "gt": ">", "apos": "'", "nbsp": " ", "rsquo": "’", "lsquo": "‘"]
        guard let re = try? NSRegularExpression(pattern: "&(#[xX][0-9a-fA-F]+|#[0-9]+|[A-Za-z]+);") else { return text }
        let ns = text as NSString
        var result = ""
        var cursor = 0
        for m in re.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            result += ns.substring(with: NSRange(location: cursor, length: m.range.location - cursor))
            let body = ns.substring(with: m.range(at: 1))
            result += decodeEntity(body, named: named) ?? ns.substring(with: m.range)
            cursor = m.range.location + m.range.length
        }
        result += ns.substring(from: cursor)
        return result
    }

    private static func decodeEntity(_ body: String, named: [String: String]) -> String? {
        if body.hasPrefix("#") {
            let digits = body.dropFirst()
            let value = digits.hasPrefix("x") || digits.hasPrefix("X")
                ? UInt32(digits.dropFirst(), radix: 16) : UInt32(digits)
            return value.flatMap(Unicode.Scalar.init).map { String(Character($0)) }
        }
        return named[body]
    }
}
