import Foundation

/// Pure helpers for machine glosses (PLAN_R10 LA2).
public enum GlossText {
    /// Whether a machine translation is worth showing for `source`. False when the trimmed gloss is empty,
    /// contains any Hangul syllable (Apple sometimes returns the Korean unchanged), or echoes the source
    /// ignoring case and whitespace.
    public static func isUsableGloss(_ gloss: String, for source: String) -> Bool {
        let g = gloss.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !g.isEmpty, !g.unicodeScalars.contains(where: Hangul.isSyllable) else { return false }
        return squashed(g) != squashed(source)
    }

    /// The particle-stripped form of `word` for a second translation pass ("사랑을" → "사랑"), or `nil` when
    /// stripping changes nothing.
    public static func fallbackForm(_ word: String) -> String? {
        let stripped = ScreenshotWords.stripParticle(word)
        return stripped != word ? stripped : nil
    }

    /// Cache key of a line gloss: the NFC text, trimmed, so a refetch that renumbers lines still hits.
    public static func lineKey(_ text: String) -> String {
        text.precomposedStringWithCanonicalMapping.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Whether `text` contains at least one Hangul syllable.
    public static func containsHangul(_ text: String) -> Bool {
        text.unicodeScalars.contains(where: Hangul.isSyllable)
    }

    private static func squashed(_ s: String) -> String {
        s.precomposedStringWithCanonicalMapping.filter { !$0.isWhitespace }.lowercased()
    }
}
