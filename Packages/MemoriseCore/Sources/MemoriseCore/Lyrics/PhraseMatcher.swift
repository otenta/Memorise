import Foundation

/// Finds multi-word deck entries inside a line's word tokens (PLAN_M6 §4.6). Greedy, longest first, left to right.
public struct PhraseMatcher: Sendable {
    private struct Phrase: Sendable {
        let words: [String]
        let entryID: String
    }

    /// Candidates by first word, longest first.
    private let byFirstWord: [String: [Phrase]]

    public var isEmpty: Bool { byFirstWord.isEmpty }

    /// `entries` in ownership order: when two entries normalise to the same phrase, the first wins.
    public init(entries: [VocabEntry]) {
        var seen = Set<[String]>()
        var index: [String: [Phrase]] = [:]
        for e in entries {
            let words = Self.normalised(e.hangul).split(separator: " ").map(String.init)
            guard words.count >= 2, seen.insert(words).inserted else { continue }
            index[words[0], default: []].append(Phrase(words: words, entryID: e.id))
        }
        byFirstWord = index.mapValues { $0.sorted { $0.words.count > $1.words.count } }
    }

    /// NFC, surrounding spaces trimmed, trailing `?!.~` dropped. A final particle is not stripped.
    public static func normalised(_ text: String) -> String {
        var s = text.precomposedStringWithCanonicalMapping.trimmingCharacters(in: .whitespaces)
        while let last = s.last, "?!.~".contains(last) { s.removeLast() }
        return s
    }

    /// Replaces each run of consecutive `.word` tokens that spells a phrase with one `.phrase`.
    public func merge(_ tokens: [LyricToken]) -> [LyricToken] {
        guard !isEmpty else { return tokens }
        var out: [LyricToken] = []
        var i = 0
        while i < tokens.count {
            if case let .word(text, _) = tokens[i],
               let (phrase, count) = match(at: i, first: text, in: tokens) {
                out.append(.phrase(text: phrase.words.joined(separator: " "), entryID: phrase.entryID, tokenRange: i...(i + count - 1)))
                i += count
            } else {
                out.append(tokens[i])
                i += 1
            }
        }
        return out
    }

    private func match(at i: Int, first: String, in tokens: [LyricToken]) -> (Phrase, Int)? {
        guard let candidates = byFirstWord[Self.normalised(first)] else { return nil }
        for p in candidates where i + p.words.count <= tokens.count {
            var ok = true
            for (k, w) in p.words.enumerated() {
                guard case let .word(text, _) = tokens[i + k], Self.normalised(text) == w else { ok = false; break }
            }
            if ok { return (p, p.words.count) }
        }
        return nil
    }
}
