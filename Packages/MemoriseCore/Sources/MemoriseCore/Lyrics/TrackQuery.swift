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

    /// One name contains the other ("BTS" vs "BTS (방탄소년단)"), key-folded.
    public static func sameArtist(_ a: String, _ b: String) -> Bool {
        let ka = key(a)
        let kb = key(b)
        guard !ka.isEmpty, !kb.isEmpty else { return false }
        return ka == kb || ka.contains(kb) || kb.contains(ka)
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
