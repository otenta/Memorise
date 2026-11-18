import Foundation

/// Turns Spotify track names into search queries and comparison keys (PLAN_M6 §4.4 step 2). Pure.
public enum TrackQuery {
    private static let suffixWords =
        "remix|live|inst|instrumental|ver|version|edit|acoustic|remaster|remastered|mix|clean|explicit|radio|sped|slowed|demo|mono|stereo"

    /// Strips `(feat. …)`, `(ft. …)`, `[…]` and ` - Remix` / ` - Live` / ` - Inst.` / ` - Japanese ver.` style suffixes.
    /// `"Seven (feat. Latto) - Clean Ver."` → `"Seven"`; `"Love wins all"` is unchanged.
    public static func normalise(_ title: String) -> String {
        var s = title
        s = replacing(s, #"\s*[\(\[]\s*(?:feat|ft|featuring|with)\b[^\)\]]*[\)\]]"#, with: "")
        s = replacing(s, #"\s*\[[^\]]*\]"#, with: "")
        s = replacing(s, #"\s+-\s+[^-]*\b(?:\#(suffixWords))\b[^-]*$"#, with: "")
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? title.trimmingCharacters(in: .whitespacesAndNewlines) : trimmed
    }

    /// Lowercased letters and digits only (Hangul kept), for tolerant name comparison.
    public static func key(_ text: String) -> String {
        Hangul.matchKey(text.precomposedStringWithCanonicalMapping.lowercased())
    }

    /// Same title after normalising and key-folding.
    public static func sameTitle(_ a: String, _ b: String) -> Bool {
        let ka = key(normalise(a))
        return !ka.isEmpty && ka == key(normalise(b))
    }

    /// Artist names match when their folded keys are equal; when the shorter key (at least 4 characters) is a
    /// prefix of the longer ("TWICE" / "TWICE (트와이스)"); or when one name appears in the other as whole words
    /// ("V" / "V (BTS)", "IU" / "IU (아이유)"). Loose containment is deliberately not enough: "V" must not match
    /// "Seventeen", nor "Rain" "Brain".
    public static func sameArtist(_ a: String, _ b: String) -> Bool {
        let ka = key(a)
        let kb = key(b)
        guard !ka.isEmpty, !kb.isEmpty else { return false }
        if ka == kb { return true }
        if min(ka.count, kb.count) >= 4, ka.hasPrefix(kb) || kb.hasPrefix(ka) { return true }
        let wa = words(a)
        let wb = words(b)
        return containsSequence(wa, wb) || containsSequence(wb, wa)
    }

    /// A Genius hit title matches one of the track's titles: same normalised title, or the hit contains the
    /// title as a whole word sequence ("Love wins all (Romanized)"). Titles under 2 key characters never match.
    public static func titleMatches(_ hitTitle: String, any titles: [String]) -> Bool {
        let hitWords = words(normalise(hitTitle))
        for t in titles {
            guard key(t).count >= 2 else { continue }
            if sameTitle(hitTitle, t) { return true }
            if containsSequence(hitWords, words(normalise(t))) { return true }
        }
        return false
    }

    /// `name` appears in `text` as whole words ("V" in "SEVENTEEN - …" is false; "BTS" in "BTS (방탄소년단) - …" is true).
    public static func containsWords(_ text: String, name: String) -> Bool {
        containsSequence(words(text), words(name))
    }

    /// Lowercased runs of letters and digits.
    static func words(_ text: String) -> [String] {
        text.precomposedStringWithCanonicalMapping.lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
    }

    private static func containsSequence(_ haystack: [String], _ needle: [String]) -> Bool {
        guard !needle.isEmpty, needle.count <= haystack.count else { return false }
        for i in 0...(haystack.count - needle.count) where Array(haystack[i..<(i + needle.count)]) == needle { return true }
        return false
    }

    /// Title candidates in search order: the normalised title, then the normalised Korean title.
    public static func titles(for track: TrackInfo) -> [String] {
        var out = [normalise(track.title)]
        if let ko = track.titleKo.map(normalise), !ko.isEmpty, !out.contains(ko) { out.append(ko) }
        return out
    }

    private static func replacing(_ s: String, _ pattern: String, with template: String) -> String {
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return s }
        return re.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: template)
    }
}
