import Foundation

/// A conjugated form drilled by `ko.conjugation` (PLAN_M4 M4-6).
public enum ConjForm: String, Codable, Sendable, CaseIterable, Hashable {
    /// Raw values are persisted and part of `ItemKey`s — never change them.
    case presentPolite, pastPolite, futurePolite, presentCasual, presentFormal, negativePolite, wantTo

    public var title: String {
        switch self {
        case .presentPolite: "present polite"
        case .pastPolite: "past polite"
        case .futurePolite: "future polite"
        case .presentCasual: "present casual"
        case .presentFormal: "present formal"
        case .negativePolite: "negative polite"
        case .wantTo: "want to"
        }
    }

    /// The ending pattern, e.g. `-아요/어요`.
    public var ending: String {
        switch self {
        case .presentPolite: "-아요/어요"
        case .pastPolite: "-았어요/었어요"
        case .futurePolite: "-(으)ㄹ 거예요"
        case .presentCasual: "-아/어"
        case .presentFormal: "-ㅂ니다/습니다"
        case .negativePolite: "안 + -아요/어요"
        case .wantTo: "-고 싶어요"
        }
    }

    /// Forms that keep the word's meaning; typed vocab accepts these as close (R5-1).
    /// `.negativePolite` is excluded: 몰라요 / 없어요 / 안 가요 mean the opposite of 알다 / 있다 / 가다.
    public static let affirmative: [ConjForm] = allCases.filter { $0 != .negativePolite }
}

/// One conjugated answer: the form, any other accepted spellings, and a one-line rule.
public struct Conjugation: Hashable, Sendable {
    /// The displayed (most common) spelling.
    public let text: String
    /// Other standard spellings that are also correct (R4-3), e.g. 보아요 for 봐요,
    /// 공부하지 않아요 / 안 공부해요 for 공부 안 해요. Never contains `text`.
    public let alternates: [String]
    public let rule: String

    public init(text: String, alternates: [String] = [], rule: String) {
        self.text = text
        var seen: Set<String> = [text]
        self.alternates = alternates.filter { seen.insert($0).inserted }
        self.rule = rule
    }

    /// `text` followed by `alternates`.
    public var accepted: [String] { [text] + alternates }
}

/// Rule-based conjugator for dictionary-form verbs/adjectives (PLAN_M4 M4-6 §2).
///
/// Order: stem extraction → irregular class → vowel harmony → contraction → ending (batchim-sensitive 으).
public enum Conjugator {
    /// Conjugates a vocab entry; `nil` when the form doesn't apply (e.g. `wantTo` on an adjective,
    /// `negativePolite` on 없다/모르다).
    public static func conjugate(_ entry: VocabEntry, _ form: ConjForm) -> Conjugation? {
        conjugate(entry.hangul, class: entry.conjugationClass, form: form, isAdjective: entry.partOfSpeech == .adjective)
    }

    public static func conjugate(_ dictionaryForm: String, class cls: ConjugationClass, form: ConjForm, isAdjective: Bool = false) -> Conjugation? {
        // Multi-word headwords: conjugate the last word, keep the rest.
        let trimmed = dictionaryForm.trimmingCharacters(in: .whitespaces)
        let (prefix, word): (String, String) = {
            guard let space = trimmed.lastIndex(of: " ") else { return ("", trimmed) }
            return (String(trimmed[...space]), String(trimmed[trimmed.index(after: space)...]))
        }()
        guard word.hasSuffix("다"), word.count >= 2 else { return nil }
        let stem = Stem(String(word.dropLast()))
        guard !stem.syllables.isEmpty else { return nil }
        guard let result = conjugate(stem, cls, form, isAdjective: isAdjective, word: word) else { return nil }
        return Conjugation(text: prefix + result.text, alternates: result.alternates.map { prefix + $0 }, rule: result.rule)
    }

    /// Every listed form of a dictionary-form predicate, main spellings and alternates (for typed matching).
    public static func allAcceptedForms(_ dictionaryForm: String, class cls: ConjugationClass,
                                        isAdjective: Bool = false,
                                        forms: [ConjForm] = ConjForm.allCases) -> [String] {
        var out: [String] = []
        var seen = Set<String>()
        for form in forms {
            for t in conjugate(dictionaryForm, class: cls, form: form, isAdjective: isAdjective)?.accepted ?? [] where seen.insert(t).inserted {
                out.append(t)
            }
        }
        return out
    }

    // MARK: - Forms

    private static func conjugate(_ stem: Stem, _ cls: ConjugationClass, _ form: ConjForm, isAdjective: Bool, word: String) -> Conjugation? {
        if cls == .copula { return copula(form) }
        switch form {
        case .presentPolite:
            let h = haeForm(stem, cls)
            return Conjugation(text: h.text + "요", alternates: optionalHaeForms(stem, cls).map { Stem($0).text + "요" },
                               rule: h.rule(endings: ("아요", "어요")))
        case .presentCasual:
            let h = haeForm(stem, cls)
            return Conjugation(text: h.text, alternates: optionalHaeForms(stem, cls).map { Stem($0).text },
                               rule: h.rule(endings: ("아", "어")))
        case .pastPolite:
            var h = haeForm(stem, cls)
            h.syllables[h.syllables.count - 1].final = Syl.ssangsiot
            let alternates = optionalHaeForms(stem, cls).map { syllables -> String in
                var s = syllables
                s[s.count - 1].final = Syl.ssangsiot
                return Stem(s).text + "어요"
            }
            return Conjugation(text: h.text + "어요", alternates: alternates, rule: h.rule(endings: ("았어요", "었어요"), past: true))
        case .futurePolite:
            return future(stem, cls)
        case .presentFormal:
            return formal(stem)
        case .wantTo:
            // Adjectives don't take -고 싶다; 없다/모르다 have no natural "want to".
            guard !isAdjective, word != "없다", word != "모르다" else { return nil }
            return Conjugation(text: stem.text + "고 싶어요", rule: "Verb stem + 고 싶어요 (\(stem.text)+고)")
        case .negativePolite:
            return negative(stem, cls, word: word, isAdjective: isAdjective)
        }
    }

    /// 이다: 이에요, 이었어요, 일 거예요, 이야, 입니다, 아니에요.
    private static func copula(_ form: ConjForm) -> Conjugation? {
        switch form {
        case .presentPolite: Conjugation(text: "이에요", rule: "이다 → 이에요 (예요 after a vowel)")
        case .pastPolite: Conjugation(text: "이었어요", rule: "이다 → 이었어요 (였어요 after a vowel)")
        case .futurePolite: Conjugation(text: "일 거예요", rule: "이 + ㄹ 거예요 → 일 거예요")
        case .presentCasual: Conjugation(text: "이야", rule: "이다 → 이야 (야 after a vowel)")
        case .presentFormal: Conjugation(text: "입니다", rule: "이 + ㅂ니다 → 입니다")
        case .negativePolite: Conjugation(text: "아니에요", rule: "The negative of 이다 is 아니다 → 아니에요")
        case .wantTo: nil
        }
    }

    /// -(으)ㄹ 거예요.
    private static func future(_ stem: Stem, _ cls: ConjugationClass) -> Conjugation {
        var s = stem
        let last = s.last
        let rule: String
        switch (cls, last.final) {
        case (.d, Syl.digeut):
            s.last.final = Syl.rieul
            s.syllables.append(.eul)
            rule = "ㄷ-irregular: ㄷ → ㄹ before 으 (\(stem.text) → \(s.text))"
        case (.b, Syl.bieup):
            s.last.final = 0
            s.syllables.append(Syl(initial: Syl.ieung, medial: Syl.u, final: Syl.rieul))
            rule = "ㅂ-irregular: ㅂ → 우 before 으 (\(stem.text) → \(s.text))"
        case (.s, Syl.siot):
            s.last.final = 0
            s.syllables.append(.eul)
            rule = "ㅅ-irregular: ㅅ drops before 으 (\(stem.text) → \(s.text))"
        case (.h, Syl.hieut):
            s.last.final = Syl.rieul
            rule = "ㅎ-irregular: ㅎ and 으 drop (\(stem.text) → \(s.text))"
        case (_, 0):
            s.last.final = Syl.rieul
            rule = "Vowel stem → ㄹ 거예요"
        case (_, Syl.rieul):
            rule = "ㄹ stem → 거예요 (no 으, no extra ㄹ)"
        default:
            s.syllables.append(.eul)
            rule = "Consonant stem → 을 거예요"
        }
        return Conjugation(text: s.text + " 거예요", rule: rule)
    }

    /// -ㅂ니다/습니다.
    private static func formal(_ stem: Stem) -> Conjugation {
        var s = stem
        switch s.last.final {
        case 0:
            s.last.final = Syl.bieup
            return Conjugation(text: s.text + "니다", rule: "Vowel stem → ㅂ니다 (\(stem.text) → \(s.text))")
        case Syl.rieul:
            s.last.final = Syl.bieup
            return Conjugation(text: s.text + "니다", rule: "ㄹ stem: ㄹ drops before ㅂ → \(s.text)니다")
        default:
            return Conjugation(text: s.text + "습니다", rule: "Consonant stem → 습니다")
        }
    }

    /// 러-irregular predicates (푸르다 → 푸르러요, 이르다 "to arrive" → 이르러요). Not modelled: as `.reu`
    /// they would produce 풀러요. 이르다 "early" is a normal 르-irregular (일러요), so it is told apart
    /// by meaning. `DeckValidator` rejects these headwords in bundled decks (R4-11).
    public static func isUnmodelledReoIrregular(_ entry: VocabEntry) -> Bool {
        guard entry.partOfSpeech?.isPredicate ?? false else { return false }
        let word = entry.hangul.split(separator: " ").last.map(String.init) ?? entry.hangul
        switch word {
        case "푸르다": return true
        case "이르다":
            return entry.meanings.contains { m in
                let m = m.lowercased()
                return m.contains("arrive") || m.contains("reach")
            }
        default: return false
        }
    }

    /// One-syllable roots of -하다 verbs that can't stand alone as nouns, so 안 can't split them off.
    static let boundHaRoots: Set<String> = ["원", "변", "피", "망", "향", "통", "상", "구", "취", "위", "정"]

    /// 안 + present polite, with the usual exceptions.
    private static func negative(_ stem: Stem, _ cls: ConjugationClass, word: String, isAdjective: Bool) -> Conjugation? {
        // No natural 안-form: 없다 / 모르다 are already negative.
        if word == "없다" || word == "모르다" { return nil }
        if word.hasSuffix("있다") {
            var s = stem
            s.last = Syl(initial: Syl.ieung, medial: Syl.eo, final: Syl.bieup_siot)
            let text = haeForm(s, .regular).text + "요"
            return Conjugation(text: text, rule: "있다 → 없다: \(text) (not 안 \(word.dropLast())어요)")
        }
        if word == "알다" {
            return Conjugation(text: "몰라요", rule: "알다 → 모르다: 몰라요 (not 안 알아요)")
        }
        let polite = haeForm(stem, cls).text + "요"
        // Long negation (-지 않아요) and uncontracted spellings are equally correct (R4-3).
        let longNegative = stem.text + "지 않아요"
        let frontAlternates = optionalHaeForms(stem, cls).map { "안 " + Stem($0).text + "요" }
        // Noun + 하다 verbs: 안 goes before 하다 (공부 안 해요). 좋아하다/싫어하다 and -하다
        // adjectives (안 필요해요) keep 안 in front.
        if cls == .ha, !isAdjective, stem.syllables.count > 1 {
            let noun = Stem(Array(stem.syllables.dropLast()))
            let lastNoun = noun.last
            let isEmotionVerb = lastNoun.final == 0 && lastNoun.initial == Syl.ieung && (lastNoun.medial == Syl.a || lastNoun.medial == Syl.eo)
            // One-syllable Sino-Korean roots that aren't nouns on their own (원하다, 변하다, 피하다)
            // take 안 in front: 안 원해요, not 원 안 해요. Real nouns (일하다 → 일 안 해요) still split.
            let isBoundRoot = noun.syllables.count == 1 && boundHaRoots.contains(noun.text)
            if !isEmotionVerb, !isBoundRoot {
                // 안 공부해요 is common in speech and accepted; 공부하지 않아요 is the long negation.
                return Conjugation(text: "\(noun.text) 안 해요", alternates: ["안 " + polite, longNegative],
                                   rule: "Noun + 하다: 안 goes before 하다 (\(noun.text) 안 해요)")
            }
        }
        return Conjugation(text: "안 " + polite, alternates: frontAlternates + [longNegative],
                           rule: "안 + present polite (\(polite))")
    }

    // MARK: - 아/어 form

    /// The 아/어 ("해") form with how it was built, for rules.
    struct HaeForm {
        var syllables: [Syl]
        let stem: Stem
        let cls: ConjugationClass
        let bright: Bool
        /// Stem's last syllable merged with 아/어 (no extra syllable added).
        let contracted: Bool

        var text: String { Stem(syllables).text }

        func rule(endings: (bright: String, dark: String), past: Bool = false) -> String {
            let ending = bright ? endings.bright : endings.dark
            let built = text
            let lastStem = stem.last.character
            switch cls {
            case .ha: return "하다 → 해 (하+여), so \(stem.text) → \(built)"
            case .d: return "ㄷ-irregular: ㄷ → ㄹ before a vowel (\(stem.text) → \(Stem(Array(syllables.dropLast())).text))"
            case .b: return "ㅂ-irregular: ㅂ → 우/오 before a vowel (\(stem.text) → \(built))"
            case .s: return "ㅅ-irregular: ㅅ drops, no contraction (\(stem.text) → \(built))"
            case .reu: return "르-irregular: 르 → ㄹ\(bright ? "라" : "러") (\(stem.text) → \(built))"
            case .eu: return "ㅡ drops (\(stem.text) → \(built))"
            case .h: return "ㅎ-irregular: ㅎ drops, vowel → ㅐ (\(stem.text) → \(built))"
            default:
                let vowel = bright ? "ㅏ/ㅗ stem" : "Other vowels"
                guard contracted else { return "\(vowel) → \(ending)" }
                let marker = bright ? (past ? "았" : "아") : (past ? "었" : "어")
                return "\(vowel) → \(ending), \(lastStem)+\(marker) → \(syllables.last!.character)"
            }
        }
    }

    /// Other standard spellings of the 아/어 form, as syllables (R4-3):
    /// - optional contraction: 보아 (봐), 주어 (줘), 되어 (돼), 마시어 (마셔), 보내어 (보내), 세어 (세).
    ///   Skipped when the last stem syllable has no initial consonant (오다 → 와 only, 배우다 → 배워 only).
    /// - 놓다: 놓아 is the main form, 놔 the accepted contraction.
    static func optionalHaeForms(_ stem: Stem, _ cls: ConjugationClass) -> [[Syl]] {
        guard let last = stem.syllables.last else { return [] }
        let main = haeForm(stem, cls)
        if cls == .regular, last == Syl.noh {
            var s = stem.syllables
            s[s.count - 1] = Syl(initial: last.initial, medial: Syl.wa)
            return [s]
        }
        guard cls == .regular || cls == .l, main.contracted, last.final == 0, last.initial != Syl.ieung else { return [] }
        let optional: Set<Int> = [Syl.o, Syl.u, Syl.i, Syl.oe, Syl.ae, Syl.e]
        guard optional.contains(last.medial) else { return [] }
        return [stem.syllables + [last.isBright ? Syl.a_ : Syl.eo_]]
    }

    static func haeForm(_ stem: Stem, _ cls: ConjugationClass) -> HaeForm {
        var s = stem.syllables
        let n = s.count
        let last = s[n - 1]
        // Harmony comes from the previous syllable for open ㅡ stems (ㅡ-drop, 르): 바쁘 → 바빠, 만들 → 만들어.
        let harmonySource = (last.medial == Syl.eu && last.final == 0 && n >= 2) ? s[n - 2] : last
        let bright = harmonySource.isBright
        let suffix = bright ? Syl.a_ : Syl.eo_
        func make(_ syllables: [Syl], contracted: Bool, bright b: Bool = bright) -> HaeForm {
            HaeForm(syllables: syllables, stem: stem, cls: cls, bright: b, contracted: contracted)
        }

        switch cls {
        case .ha where last == Syl.ha:
            s[n - 1].medial = Syl.ae
            return make(s, contracted: true, bright: true)
        case .h where last.final == Syl.hieut:
            s[n - 1].final = 0
            s[n - 1].medial = Syl.hMedial[last.medial] ?? Syl.ae
            return make(s, contracted: true)
        case .d where last.final == Syl.digeut:
            s[n - 1].final = Syl.rieul
            return make(s + [suffix], contracted: false)
        case .b where last.final == Syl.bieup:
            s[n - 1].final = 0
            // Only 돕다/곱다 (one-syllable ㅗ stems) keep 와.
            let wa = n == 1 && last.medial == Syl.o
            return make(s + [Syl(initial: Syl.ieung, medial: wa ? Syl.wa : Syl.wo)], contracted: false, bright: wa)
        case .s where last.final == Syl.siot:
            s[n - 1].final = 0
            return make(s + [suffix], contracted: false)
        case .reu where last == Syl.reu && n >= 2:
            s[n - 2].final = Syl.rieul
            s[n - 1].medial = bright ? Syl.a : Syl.eo
            return make(s, contracted: true)
        default:
            break
        }

        guard last.final == 0 else { return make(s + [suffix], contracted: false) }
        switch last.medial {
        case Syl.eu:
            s[n - 1].medial = bright ? Syl.a : Syl.eo
            return make(s, contracted: true)
        case Syl.a, Syl.eo, Syl.ae, Syl.e, Syl.yeo:
            return make(s, contracted: true)
        case Syl.o:
            s[n - 1].medial = Syl.wa
            return make(s, contracted: true)
        case Syl.u:
            s[n - 1].medial = Syl.wo
            return make(s, contracted: true)
        case Syl.i:
            s[n - 1].medial = Syl.yeo
            return make(s, contracted: true)
        case Syl.oe:
            s[n - 1].medial = Syl.wae
            return make(s, contracted: true)
        default:
            return make(s + [suffix], contracted: false)
        }
    }
}

// MARK: - Syllable arithmetic

/// A Hangul syllable as (initial, medial, final) indices into `Hangul.initials/medials/finals`.
struct Syl: Hashable, Sendable {
    var initial: Int
    var medial: Int
    var final: Int

    init(initial: Int, medial: Int, final: Int = 0) {
        self.initial = initial
        self.medial = medial
        self.final = final
    }

    var character: Character { Hangul.compose(initial: initial, medial: medial, final: final) }
    /// ㅏ, ㅑ, ㅗ take 아.
    var isBright: Bool { medial == Syl.a || medial == Syl.ya || medial == Syl.o }

    // Initials.
    static let rieulInitial = 5, ieung = 11, hieutInitial = 18
    // Medials.
    static let a = 0, ae = 1, ya = 2, yae = 3, eo = 4, e = 5, yeo = 6, ye = 7, o = 8, wa = 9, wae = 10, oe = 11
    static let u = 13, wo = 14, eu = 18, i = 20
    // Finals.
    static let digeut = 7, rieul = 8, bieup = 17, bieup_siot = 18, siot = 19, ssangsiot = 20, hieut = 27

    static let ha = Syl(initial: hieutInitial, medial: a)
    /// 놓 (놓다 → 놓아요 / 놔요).
    static let noh = Syl(initial: 2, medial: o, final: hieut)
    static let reu = Syl(initial: rieulInitial, medial: eu)
    static let a_ = Syl(initial: ieung, medial: a)
    static let eo_ = Syl(initial: ieung, medial: eo)
    static let eul = Syl(initial: ieung, medial: eu, final: rieul)
    /// ㅎ-irregular vowel change: ㅏ/ㅓ → ㅐ, ㅑ/ㅕ → ㅒ/ㅖ.
    static let hMedial: [Int: Int] = [a: ae, eo: ae, ya: yae, yeo: ye]
}

/// A stem as syllables (non-syllable characters are dropped).
struct Stem: Hashable, Sendable {
    var syllables: [Syl]

    init(_ syllables: [Syl]) { self.syllables = syllables }

    init(_ text: String) {
        syllables = text.unicodeScalars.compactMap(Hangul.decompose).map { Syl(initial: $0.initial, medial: $0.medial, final: $0.final) }
    }

    var last: Syl {
        get { syllables[syllables.count - 1] }
        set { syllables[syllables.count - 1] = newValue }
    }

    var text: String { String(syllables.map(\.character)) }
}
