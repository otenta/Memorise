import Foundation

/// Splits lyric lines into tappable words and plain text (PLAN_M6 §4.6). Pure.
public enum LyricsTokenizer {
    /// Characters trimmed from both ends of a word and emitted as `.plain`.
    static let trimmed: Set<Character> = [
        ".", ",", "!", "?", "~", "…", "\"", "'", "(", ")", "[", "]", "「", "」", "“", "”", "‘", "’", ":", ";",
    ]

    /// Tokens for one line, phrases merged when `phrases` is given. Section headers produce none.
    public static func tokens(for line: LyricLine, phrases: PhraseMatcher? = nil) -> [LyricToken] {
        guard !line.isSectionHeader else { return [] }
        let words = wordTokens(in: line.text)
        guard let phrases, !phrases.isEmpty else { return words }
        return phrases.merge(words)
    }

    /// Tokens for one line without phrase merging. A `.phrase`'s `tokenRange` indexes this array.
    public static func wordTokens(in text: String) -> [LyricToken] {
        var tokens: [LyricToken] = []
        var offset = 0
        var chunk = ""
        var chunkStart = 0
        func flush() {
            guard !chunk.isEmpty else { return }
            tokens.append(contentsOf: chunkTokens(chunk, start: chunkStart))
            chunk = ""
        }
        for ch in text {
            if ch.isWhitespace {
                flush()
            } else {
                if chunk.isEmpty { chunkStart = offset }
                chunk.append(ch)
            }
            offset += 1
        }
        flush()
        return tokens
    }

    private static func chunkTokens(_ chunk: String, start: Int) -> [LyricToken] {
        guard chunk.unicodeScalars.contains(where: Hangul.isSyllable) else { return [.plain(chunk)] }
        let chars = Array(chunk)
        var lo = 0
        var hi = chars.count
        while lo < hi, trimmed.contains(chars[lo]) { lo += 1 }
        while hi > lo, trimmed.contains(chars[hi - 1]) { hi -= 1 }
        var out: [LyricToken] = []
        if lo > 0 { out.append(.plain(String(chars[0..<lo]))) }
        out.append(.word(text: String(chars[lo..<hi]), range: (start + lo)..<(start + hi)))
        if hi < chars.count { out.append(.plain(String(chars[hi...]))) }
        return out
    }
}
