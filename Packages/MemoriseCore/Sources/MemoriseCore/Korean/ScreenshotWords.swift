/// Turns OCR'd screenshot lines into candidate words (PLAN_M4 M4-9 §3). Pure; OCR lives in the app.
public enum ScreenshotWords {
    /// Particles stripped (one, trailing) when ≥ 2 syllables remain. Longest first, so 으로/에서 win over 로/에.
    public static let particles = ["으로", "에서", "한테", "은", "는", "이", "가", "을", "를", "에", "의", "도", "만", "로", "과", "와", "께"]
        .sorted { $0.count > $1.count }

    public struct Result: Hashable, Sendable {
        /// New words, in first-seen order.
        public var words: [String]
        /// Words already in some deck (shown as "already known (n)").
        public var known: [String]
    }

    /// Hangul runs of each line → particle stripped → deduplicated → split into new / known.
    public static func extract(lines: [String], knownHangul: Set<String>) -> Result {
        var seen = Set<String>()
        var result = Result(words: [], known: [])
        for line in lines {
            for run in hangulRuns(line) {
                let word = stripParticle(run)
                guard seen.insert(word).inserted else { continue }
                if knownHangul.contains(word) || knownHangul.contains(run) {
                    result.known.append(word)
                } else {
                    result.words.append(word)
                }
            }
        }
        return result
    }

    /// Maximal runs of precomposed syllables ("검을 들어라!" → ["검을", "들어라"]).
    public static func hangulRuns(_ text: String) -> [String] {
        var runs: [String] = []
        var current = String.UnicodeScalarView()
        for s in text.unicodeScalars {
            if Hangul.isSyllable(s) {
                current.append(s)
            } else if !current.isEmpty {
                runs.append(String(current))
                current = String.UnicodeScalarView()
            }
        }
        if !current.isEmpty { runs.append(String(current)) }
        return runs
    }

    /// Removes one trailing particle when the remainder keeps ≥ 2 syllables ("무기를" → "무기", "검을" stays).
    public static func stripParticle(_ word: String) -> String {
        // The longest matching particle decides: 집으로 must not fall back to 로 and leave 집으.
        guard let p = particles.first(where: word.hasSuffix) else { return word }
        let rest = String(word.dropLast(p.count))
        return Hangul.syllableCount(rest) >= 2 ? rest : word
    }
}

#if DEBUG
public extension ScreenshotWords {
    /// Ten sample tokens (M4-9 accept). Returns errors (empty = OK).
    static func selfCheck() -> [String] {
        let samples: [(String, String)] = [
            ("무기를", "무기"), ("던전에서", "던전"), ("검을", "검을"), ("마법사가", "마법사"), ("길드의", "길드"),
            ("파티와", "파티"), ("보스는", "보스"), ("물약", "물약"), ("마을로", "마을"), ("집으로", "집으로"),
        ]
        var errors = samples.compactMap { input, expected in
            stripParticle(input) == expected ? nil : "ScreenshotWords: \(input) → \(stripParticle(input)), expected \(expected)"
        }
        let r = extract(lines: ["무기를 강화하세요! 무기", "HP 100 보스는"], knownHangul: ["보스"])
        if r.words != ["무기", "강화하세요"] || r.known != ["보스"] { errors.append("ScreenshotWords: extract \(r)") }
        return errors
    }
}
#endif
