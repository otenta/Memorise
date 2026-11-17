import Foundation

/// How a typed answer is compared with the expected answers.
public enum AnswerMatchKind: String, Sendable, Hashable {
    case hangul, english, romanization
}

/// What a typed answer is checked against.
public struct TypedAnswerSpec: Sendable, Hashable {
    /// Every accepted answer (any one matches). The first is shown as "expected".
    public let expected: [String]
    public let kind: AnswerMatchKind
    /// When true, a `.close` verdict counts as wrong (spelling is the skill, e.g. conjugation).
    public let exactRequired: Bool
    /// Hangul: also accept a conjugated form of the dictionary form (가요 for 가다) as close.
    public let isPredicate: Bool
    /// Predicates: conjugation class used to generate the accepted conjugated forms (R4-2).
    public let conjugationClass: ConjugationClass
    /// Predicates: adjectives have no `wantTo` form.
    public let isAdjective: Bool

    public init(
        expected: [String], kind: AnswerMatchKind, exactRequired: Bool = false, isPredicate: Bool = false,
        conjugationClass: ConjugationClass = .regular, isAdjective: Bool = false
    ) {
        self.expected = expected
        self.kind = kind
        self.exactRequired = exactRequired
        self.isPredicate = isPredicate
        self.conjugationClass = conjugationClass
        self.isAdjective = isAdjective
    }
}

/// Result of an automatically checked answer.
public enum AnswerVerdict: String, Sendable, Hashable {
    case exact, close, wrong

    /// Grade stored for this verdict. "Close" is correct unless `exactRequired`.
    public func isCorrect(exactRequired: Bool) -> Bool {
        switch self {
        case .exact: true
        case .close: !exactRequired
        case .wrong: false
        }
    }
}

/// Fuzzy answer checking for typed answers (PLAN_M4 M4-4).
public enum AnswerMatcher {
    public struct Result: Sendable, Hashable {
        public let verdict: AnswerVerdict
        /// The expected answer closest to the input (for the diff).
        public let closest: String
    }

    public static func match(input: String, spec: TypedAnswerSpec) -> Result {
        match(input: input, expected: spec.expected, kind: spec.kind, isPredicate: spec.isPredicate,
              conjugationClass: spec.conjugationClass, isAdjective: spec.isAdjective)
    }

    public static func match(
        input: String, expected: [String], kind: AnswerMatchKind, isPredicate: Bool = false,
        conjugationClass: ConjugationClass = .regular, isAdjective: Bool = false
    ) -> Result {
        let fallback = expected.first ?? ""
        guard !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !expected.isEmpty else {
            return Result(verdict: .wrong, closest: fallback)
        }
        var best = Result(verdict: .wrong, closest: fallback)
        for e in expected {
            let v: AnswerVerdict = switch kind {
            case .hangul: hangulVerdict(input, e, isPredicate: isPredicate, conjugationClass: conjugationClass, isAdjective: isAdjective)
            case .english: englishVerdict(input, e)
            case .romanization: romanizationVerdict(input, e)
            }
            if v == .exact { return Result(verdict: .exact, closest: e) }
            if v == .close, best.verdict == .wrong { best = Result(verdict: .close, closest: e) }
        }
        return best
    }

    // MARK: Hangul

    /// Hangul rules (R4-2, PLAN §17):
    /// - Predicates: a real affirmative conjugation of the expected word (any `ConjForm.affirmative`
    ///   form, main spelling or alternate, with or without the polite 요) is close. Negative forms
    ///   (몰라요 for 알다, 없어요 for 있다, 안 가요 for 가다) are wrong (R5-1). A bare stem or another
    ///   word sharing the first syllable (가방 for 가다) is not close either.
    /// - Words of 1–2 syllables: only a final-consonant (batchim) slip in one syllable is close;
    ///   changing an initial or a vowel makes a different word (의사/의자) and is wrong.
    /// - Longer words: jamo distance ≤ 1 is close.
    static func hangulVerdict(
        _ input: String, _ expected: String, isPredicate: Bool,
        conjugationClass: ConjugationClass = .regular, isAdjective: Bool = false
    ) -> AnswerVerdict {
        let a = normalizedHangul(input)
        let b = normalizedHangul(expected)
        guard !a.isEmpty, !b.isEmpty else { return .wrong }
        if a == b { return .exact }
        if isPredicate, b.hasSuffix("다") {
            let forms = Conjugator.allAcceptedForms(expected, class: conjugationClass, isAdjective: isAdjective,
                                                    forms: ConjForm.affirmative)
            for form in forms.map(normalizedHangul) where !form.isEmpty {
                // 먹어요 / 먹어 / 먹었어요 for 먹다.
                if a == form { return .close }
                if form.hasSuffix("요"), a == String(form.dropLast()) { return .close }
            }
        }
        let syllables = Hangul.syllableCount(b)
        guard syllables >= 2 else { return .wrong }
        if syllables <= 2 { return isBatchimSlip(a, b) ? .close : .wrong }
        return editDistance(Hangul.jamo(a), Hangul.jamo(b)) <= 1 ? .close : .wrong
    }

    /// Same syllables except one, which differs only in its final consonant (있다/잇다, 많이/만이).
    static func isBatchimSlip(_ a: String, _ b: String) -> Bool {
        let x = Array(a.unicodeScalars), y = Array(b.unicodeScalars)
        guard x.count == y.count else { return false }
        var differences = 0
        for (p, q) in zip(x, y) where p != q {
            guard let dp = Hangul.decompose(p), let dq = Hangul.decompose(q),
                  dp.initial == dq.initial, dp.medial == dq.medial else { return false }
            differences += 1
        }
        return differences == 1
    }

    /// NFC; keeps Hangul syllables and jamo only (spaces and punctuation stripped).
    static func normalizedHangul(_ s: String) -> String {
        String(String.UnicodeScalarView(s.precomposedStringWithCanonicalMapping.unicodeScalars.filter {
            Hangul.isSyllable($0) || (0x3131...0x318E).contains($0.value) || (0x1100...0x11FF).contains($0.value)
        }))
    }

    // MARK: English

    /// Close = a typo made of dropped or extra letters only (R4-2, PLAN §17): one at ≥ 5 letters,
    /// two at ≥ 9. Substitutions and transpositions are wrong, because they mostly produce other
    /// real words (three/there, angel/angle, quite/quiet).
    static func englishVerdict(_ input: String, _ expected: String) -> AnswerVerdict {
        let a = normalizedEnglish(input)
        let glosses = expected.split(whereSeparator: { $0 == "/" || $0 == ";" }).map { normalizedEnglish(stripParentheticals(String($0))) }
        var best = AnswerVerdict.wrong
        for b in glosses where !b.isEmpty {
            if a == b { return .exact }
            let d = indelDistance(Array(a), Array(b))
            if (b.count >= 9 && d <= 2) || (b.count >= 5 && d <= 1) { best = .close }
        }
        return best
    }

    /// Edit distance with insertions and deletions only (`|a| + |b| − 2·LCS`).
    static func indelDistance<T: Equatable>(_ a: [T], _ b: [T]) -> Int {
        guard !a.isEmpty, !b.isEmpty else { return a.count + b.count }
        var prev = Array(repeating: 0, count: b.count + 1)
        var cur = prev
        for i in 1...a.count {
            for j in 1...b.count {
                cur[j] = a[i - 1] == b[j - 1] ? prev[j - 1] + 1 : max(prev[j], cur[j - 1])
            }
            swap(&prev, &cur)
        }
        return a.count + b.count - 2 * prev[b.count]
    }

    static func normalizedEnglish(_ s: String) -> String {
        var t = s.lowercased()
            .replacingOccurrences(of: "’", with: "'")
            .components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
        t = t.trimmingCharacters(in: CharacterSet.punctuationCharacters.union(.whitespaces))
        for article in ["to ", "a ", "an ", "the "] where t.hasPrefix(article) {
            t.removeFirst(article.count)
            break
        }
        return t.trimmingCharacters(in: .whitespaces)
    }

    /// `"bag (for carrying)"` → `"bag"`.
    static func stripParentheticals(_ s: String) -> String {
        var out = ""
        var depth = 0
        for ch in s {
            if ch == "(" { depth += 1; continue }
            if ch == ")" { depth = max(0, depth - 1); continue }
            if depth == 0 { out.append(ch) }
        }
        return out
    }

    // MARK: Romanization

    /// Exact after lowercasing and stripping spaces/hyphens/apostrophes; `r` and `l` (ㄹ) are interchangeable.
    static func romanizationVerdict(_ input: String, _ expected: String) -> AnswerVerdict {
        normalizedRomanization(input) == normalizedRomanization(expected) ? .exact : .wrong
    }

    static func normalizedRomanization(_ s: String) -> String {
        String(s.lowercased().filter { $0.isLetter }.map { $0 == "r" ? "l" : $0 })
    }

    // MARK: Distance

    /// Optimal-string-alignment distance (Levenshtein plus adjacent transpositions).
    static func editDistance<T: Equatable>(_ a: [T], _ b: [T]) -> Int {
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var d = Array(repeating: Array(repeating: 0, count: b.count + 1), count: a.count + 1)
        for i in 0...a.count { d[i][0] = i }
        for j in 0...b.count { d[0][j] = j }
        for i in 1...a.count {
            for j in 1...b.count {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                d[i][j] = min(d[i - 1][j] + 1, d[i][j - 1] + 1, d[i - 1][j - 1] + cost)
                if i > 1, j > 1, a[i - 1] == b[j - 2], a[i - 2] == b[j - 1] {
                    d[i][j] = min(d[i][j], d[i - 2][j - 2] + 1)
                }
            }
        }
        return d[a.count][b.count]
    }

    // MARK: Diff

    /// Characters of `input` with a flag for those not matching `expected` (LCS-based), for highlighting.
    public static func diff(_ input: String, against expected: String) -> [(character: Character, matches: Bool)] {
        let a = Array(input), b = Array(expected)
        guard !a.isEmpty else { return [] }
        var l = Array(repeating: Array(repeating: 0, count: b.count + 1), count: a.count + 1)
        for i in stride(from: a.count - 1, through: 0, by: -1) {
            for j in stride(from: b.count - 1, through: 0, by: -1) {
                l[i][j] = a[i] == b[j] ? l[i + 1][j + 1] + 1 : max(l[i + 1][j], l[i][j + 1])
            }
        }
        var out: [(Character, Bool)] = []
        var i = 0, j = 0
        while i < a.count {
            if j < b.count, a[i] == b[j] {
                out.append((a[i], true)); i += 1; j += 1
            } else if j < b.count, l[i][j + 1] >= l[i + 1][j] {
                j += 1
            } else {
                out.append((a[i], false)); i += 1
            }
        }
        return out
    }
}

public extension Hangul {
    static let initials = ["ㄱ", "ㄲ", "ㄴ", "ㄷ", "ㄸ", "ㄹ", "ㅁ", "ㅂ", "ㅃ", "ㅅ", "ㅆ", "ㅇ", "ㅈ", "ㅉ", "ㅊ", "ㅋ", "ㅌ", "ㅍ", "ㅎ"]
    static let medials = ["ㅏ", "ㅐ", "ㅑ", "ㅒ", "ㅓ", "ㅔ", "ㅕ", "ㅖ", "ㅗ", "ㅘ", "ㅙ", "ㅚ", "ㅛ", "ㅜ", "ㅝ", "ㅞ", "ㅟ", "ㅠ", "ㅡ", "ㅢ", "ㅣ"]
    /// Index 0 = no final.
    static let finals = ["", "ㄱ", "ㄲ", "ㄳ", "ㄴ", "ㄵ", "ㄶ", "ㄷ", "ㄹ", "ㄺ", "ㄻ", "ㄼ", "ㄽ", "ㄾ", "ㄿ", "ㅀ", "ㅁ", "ㅂ", "ㅄ", "ㅅ", "ㅆ", "ㅇ", "ㅈ", "ㅊ", "ㅋ", "ㅌ", "ㅍ", "ㅎ"]

    /// (initial, medial, final) indices of a precomposed syllable.
    static func decompose(_ s: Unicode.Scalar) -> (initial: Int, medial: Int, final: Int)? {
        guard isSyllable(s) else { return nil }
        let v = Int(s.value) - 0xAC00
        return (v / (21 * 28), (v % (21 * 28)) / 28, v % 28)
    }

    /// Composes a syllable from indices (`0xAC00 + (initial*21 + medial)*28 + final`).
    static func compose(initial: Int, medial: Int, final: Int = 0) -> Character {
        Character(Unicode.Scalar(UInt32(0xAC00 + (initial * 21 + medial) * 28 + final))!)
    }

    /// Final-consonant index of the last syllable (0 = ends in a vowel; `nil` = no syllable).
    static func finalIndex(of text: String) -> Int? {
        text.unicodeScalars.last(where: isSyllable).flatMap(decompose)?.final
    }

    /// Jamo sequence (compound vowels/finals count as one symbol); other characters pass through.
    static func jamo(_ text: String) -> [String] {
        var out: [String] = []
        for s in text.unicodeScalars {
            if let d = decompose(s) {
                out.append(initials[d.initial])
                out.append(medials[d.medial])
                if d.final != 0 { out.append(finals[d.final]) }
            } else {
                out.append(String(s))
            }
        }
        return out
    }
}
