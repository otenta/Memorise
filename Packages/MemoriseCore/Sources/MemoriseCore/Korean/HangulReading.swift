/// Revised Romanization for **isolated syllables only** (PLAN_M4 M4-2).
///
/// Words are never auto-romanized (liaison and assimilation rules); real words use their deck's romanization.
public enum Romanizer {
    /// Indexed like `Hangul.initials`. Initial ㅇ is silent.
    static let initials = ["g", "kk", "n", "d", "tt", "r", "m", "b", "pp", "s", "ss", "", "j", "jj", "ch", "k", "t", "p", "h"]
    /// Indexed like `Hangul.medials`.
    static let medials = ["a", "ae", "ya", "yae", "eo", "e", "yeo", "ye", "o", "wa", "wae", "oe", "yo", "u", "wo", "we", "wi", "yu", "eu", "ui", "i"]
    /// Indexed like `Hangul.finals`: the representative sound (k, n, t, l, m, p, ng).
    static let finals = ["", "k", "k", "k", "n", "n", "n", "t", "l", "k", "m", "l", "l", "l", "p", "l", "m", "p", "p", "t", "t", "ng", "t", "t", "k", "t", "p", "t"]

    /// Romanization of one precomposed syllable, or `nil` for anything else.
    public static func syllable(_ s: Unicode.Scalar) -> String? {
        guard let d = Hangul.decompose(s) else { return nil }
        return initials[d.initial] + medials[d.medial] + finals[d.final]
    }

    /// Romanization of a single-syllable string, or `nil`.
    public static func syllable(_ text: String) -> String? {
        let scalars = text.unicodeScalars
        guard scalars.count == 1, let s = scalars.first else { return nil }
        return syllable(s)
    }
}

/// Options for `ko.hangul`.
public struct HangulReadingOptions: Hashable, Codable, Sendable {
    public enum Stage: String, Codable, Sendable, CaseIterable, Hashable {
        /// Raw values are persisted — never change them.
        case basicVowels, basicConsonants, aspiratedTense, complexVowels, syllables, batchim, realWords

        public var title: String {
            switch self {
            case .basicVowels: "Basic vowels"
            case .basicConsonants: "Basic consonants"
            case .aspiratedTense: "Aspirated & tense"
            case .complexVowels: "Complex vowels"
            case .syllables: "Syllables"
            case .batchim: "Batchim"
            case .realWords: "Real words"
            }
        }

        public var subtitle: String {
            switch self {
            case .basicVowels: "ㅏ ㅓ ㅗ ㅜ ㅡ ㅣ ㅑ ㅕ ㅛ ㅠ"
            case .basicConsonants: "ㄱ ㄴ ㄷ ㄹ ㅁ ㅂ ㅅ ㅇ ㅈ ㅎ"
            case .aspiratedTense: "ㅋ ㅌ ㅍ ㅊ ㄲ ㄸ ㅃ ㅆ ㅉ"
            case .complexVowels: "ㅐ ㅔ ㅒ ㅖ ㅘ ㅙ ㅚ ㅝ ㅞ ㅟ ㅢ"
            case .syllables: "가 나 다 … 하 to 히"
            case .batchim: "Final consonants: 각 산 밥 …"
            case .realWords: "Short words from your Korean decks"
            }
        }
    }

    public var stages: Set<Stage>
    /// Unseen cards introduced per session (in stage order).
    public var newPerSession: Int

    public init(stages: Set<Stage> = [.basicVowels, .basicConsonants], newPerSession: Int = 8) {
        self.stages = stages
        self.newPerSession = newPerSession
    }

    private enum CodingKeys: String, CodingKey { case stages, newPerSession }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = HangulReadingOptions()
        let decoded = c.tolerant(Set<Stage>.self, .stages, d.stages)
        stages = decoded.isEmpty ? d.stages : decoded
        newPerSession = max(0, c.tolerant(Int.self, .newPerSession, d.newPerSession))
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(newPerSession, forKey: .newPerSession)
        try c.encode(sortedRaw(stages), forKey: .stages)
    }
}

/// "How do you read 가?"
public struct HangulReadingPrompt: Hashable, Sendable {
    public typealias Stage = HangulReadingOptions.Stage

    public let stage: Stage
    /// What is shown (a syllable, or a short word).
    public let text: String
    /// Expected romanization.
    public let romanization: String
    /// The letter being taught (letter stages only), e.g. `ㄱ`.
    public let jamo: String?
    /// Source entry (`realWords` only).
    public let entry: VocabEntry?
    /// Introduction order (stage, then table order).
    public let rank: Int

    public init(stage: Stage, text: String, romanization: String, jamo: String? = nil, entry: VocabEntry? = nil, rank: Int) {
        self.stage = stage
        self.text = text
        self.romanization = romanization
        self.jamo = jamo
        self.entry = entry
        self.rank = rank
    }

    /// Initial / medial indices of the first syllable (for pattern penalties).
    var firstSyllable: (initial: Int, medial: Int, final: Int)? {
        text.unicodeScalars.first.flatMap(Hangul.decompose)
    }
}

/// `ko.hangul` — letters and syllables to sounds, generated from Unicode composition.
public struct HangulReadingDeck: Deck {
    public typealias Stage = HangulReadingOptions.Stage
    public static let deckID: DeckID = "ko.hangul"

    public let id: DeckID = HangulReadingDeck.deckID
    public let kind = DeckKind.hangulReading
    public let title = "Hangul Reading"
    public let subtitle = "Letters to sounds"
    public let subject = Subject.korean
    /// 1–3-syllable words from every Korean deck (deduplicated by spelling).
    public let realWords: [VocabEntry]

    public init(vocab: [VocabDeck] = []) {
        var seen = Set<String>()
        var words: [VocabEntry] = []
        for deck in vocab where deck.subject == .korean {
            for e in deck.entries where Self.isReadableWord(e) && seen.insert(e.hangul).inserted {
                words.append(e)
            }
        }
        // Shortest words first, then deck order.
        realWords = words.enumerated()
            .sorted { (Hangul.syllableCount($0.element.hangul), $0.offset) < (Hangul.syllableCount($1.element.hangul), $1.offset) }
            .map(\.element)
    }

    static func isReadableWord(_ e: VocabEntry) -> Bool {
        let n = Hangul.syllableCount(e.hangul)
        return (1...3).contains(n) && e.hangul.unicodeScalars.count == n
            && !e.romanization.trimmingCharacters(in: .whitespaces).isEmpty
            && e.partOfSpeech != .pattern
    }

    public var defaultOptions: DeckOptions { .hangulReading(HangulReadingOptions()) }

    // MARK: Tables

    static let basicVowels = ["ㅏ", "ㅓ", "ㅗ", "ㅜ", "ㅡ", "ㅣ", "ㅑ", "ㅕ", "ㅛ", "ㅠ"]
    static let basicConsonants = ["ㄱ", "ㄴ", "ㄷ", "ㄹ", "ㅁ", "ㅂ", "ㅅ", "ㅇ", "ㅈ", "ㅎ"]
    static let aspiratedTense = ["ㅋ", "ㅌ", "ㅍ", "ㅊ", "ㄲ", "ㄸ", "ㅃ", "ㅆ", "ㅉ"]
    static let complexVowels = ["ㅐ", "ㅔ", "ㅒ", "ㅖ", "ㅘ", "ㅙ", "ㅚ", "ㅝ", "ㅞ", "ㅟ", "ㅢ"]
    /// 14 basic initials for the `syllables` grid.
    static let syllableInitials = ["ㄱ", "ㄴ", "ㄷ", "ㄹ", "ㅁ", "ㅂ", "ㅅ", "ㅇ", "ㅈ", "ㅊ", "ㅋ", "ㅌ", "ㅍ", "ㅎ"]
    /// Common syllables with a single final consonant (no double finals such as 닭).
    static let batchimSyllables: [String] = {
        let list = """
        각 간 갈 감 갑 강 같 건 걸 검 것 경 곧 골 곰 공 국 군 굴 금 길 김 꽃 꿈 \
        난 날 남 년 놀 농 눈 단 달 담 답 당 돈 돌 동 들 등 딸 땅 떡 \
        만 말 맛 먹 먼 멋 면 명 목 몸 못 문 물 믿 밖 박 반 받 발 밤 밥 방 밭 \
        번 법 별 병 복 본 봄 분 불 빛 빵 산 살 삼 상 생 선 설 섬 성 속 손 술 숲 식 신 실 쌀 \
        안 알 앞 약 양 언 얼 엉 역 연 열 영 옆 옷 왕 용 울 웃 월 은 을 음 인 일 입 있 \
        잘 잠 장 전 절 점 정 종 죽 준 줄 중 집 창 책 첫 청 춤 친 칼 콩 큰 \
        탑 통 팔 팥 편 학 한 할 함 합 힘
        """
        var seen = Set<String>()
        return list.split(whereSeparator: \.isWhitespace).map(String.init).filter { s in
            // Single finals only (double finals are excluded by design).
            guard let d = s.unicodeScalars.first.flatMap(Hangul.decompose), d.final != 0,
                  !Self.doubleFinals.contains(d.final) else { return false }
            return seen.insert(s).inserted
        }
    }()

    /// ㄳ ㄵ ㄶ ㄺ ㄻ ㄼ ㄽ ㄾ ㄿ ㅀ ㅄ.
    static let doubleFinals: Set<Int> = [3, 5, 6, 9, 10, 11, 12, 13, 14, 15, 18]

    static func initialIndex(_ jamo: String) -> Int { Hangul.initials.firstIndex(of: jamo)! }
    static func medialIndex(_ jamo: String) -> Int { Hangul.medials.firstIndex(of: jamo)! }

    static func stageOrder(_ s: Stage) -> Int { Stage.allCases.firstIndex(of: s)! }

    // MARK: Cards

    public static func itemKey(_ prompt: HangulReadingPrompt) -> ItemKey {
        switch prompt.stage {
        case .basicVowels, .complexVowels: ItemKey("hangul:v:\(prompt.jamo ?? prompt.text)")
        case .basicConsonants, .aspiratedTense: ItemKey("hangul:c:\(prompt.jamo ?? prompt.text)")
        case .syllables, .batchim: ItemKey("hangul:s:\(prompt.text)")
        case .realWords: ItemKey("hangul:w:\(prompt.entry?.id ?? prompt.text)")
        }
    }

    /// Every prompt of a stage, in table order.
    public func prompts(for stage: Stage) -> [HangulReadingPrompt] {
        let base = Self.stageOrder(stage) * 10_000
        func syllable(_ i: Int, _ m: Int, _ f: Int = 0) -> String { String(Hangul.compose(initial: i, medial: m, final: f)) }
        func make(_ text: String, jamo: String? = nil, entry: VocabEntry? = nil, _ order: Int) -> HangulReadingPrompt {
            let roman = entry?.romanization ?? Romanizer.syllable(text) ?? ""
            return HangulReadingPrompt(stage: stage, text: text, romanization: roman, jamo: jamo, entry: entry, rank: base + order)
        }
        let silent = Self.initialIndex("ㅇ"), a = Self.medialIndex("ㅏ")
        switch stage {
        case .basicVowels, .complexVowels:
            let table = stage == .basicVowels ? Self.basicVowels : Self.complexVowels
            return table.enumerated().map { make(syllable(silent, Self.medialIndex($1)), jamo: $1, $0) }
        case .basicConsonants, .aspiratedTense:
            let table = stage == .basicConsonants ? Self.basicConsonants : Self.aspiratedTense
            return table.enumerated().map { make(syllable(Self.initialIndex($1), a), jamo: $1, $0) }
        case .syllables:
            // Vowel-major so each session's new cards share a vowel and vary the consonant.
            var out: [HangulReadingPrompt] = []
            for v in Self.basicVowels {
                for c in Self.syllableInitials {
                    out.append(make(syllable(Self.initialIndex(c), Self.medialIndex(v)), out.count))
                }
            }
            return out
        case .batchim:
            return Self.batchimSyllables.enumerated().map { make($1, $0) }
        case .realWords:
            return realWords.enumerated().map { make($1.hangul, entry: $1, $0) }
        }
    }

    public func cards(options: DeckOptions) -> [Card] {
        guard case let .hangulReading(o) = options else { return [] }
        return Stage.allCases.filter(o.stages.contains).flatMap { stage in
            prompts(for: stage).map { Card(key: Self.itemKey($0), deckID: id, content: .hangulReading($0)) }
        }
    }

    public func introductionRank(of card: Card) -> Int? { card.hangulReading?.rank }

    public func newPerSession(options: DeckOptions) -> Int? { options.hangulReading?.newPerSession }

    /// Same text ×0.1 (e.g. 아 as ㅏ and as ㅇ); same initial ×0.6; same vowel ×0.7.
    public func patternPenalty(candidate: Card, recent: ArraySlice<Card>) -> Double {
        guard let c = candidate.hangulReading, let p = recent.back(0)?.hangulReading else { return 1 }
        if c.text == p.text { return 0.1 }
        guard let cs = c.firstSyllable, let ps = p.firstSyllable else { return 1 }
        var penalty = 1.0
        if cs.initial == ps.initial { penalty *= 0.6 }
        if cs.medial == ps.medial { penalty *= 0.7 }
        return penalty
    }
}

#if DEBUG
public extension HangulReadingDeck {
    /// Reference romanizations and stage counts (PLAN_M4 M4-2 §6). Returns errors (empty = OK).
    static func selfCheck() -> [String] {
        var errors: [String] = []
        let reference = ["가": "ga", "꿈": "kkum", "밥": "bap", "산": "san", "의": "ui", "쥐": "jwi", "왜": "wae", "첫": "cheot", "엉": "eong", "라": "ra", "달": "dal"]
        for (s, r) in reference where Romanizer.syllable(s) != r {
            errors.append("Romanizer: \(s) → \(Romanizer.syllable(s) ?? "nil"), expected \(r)")
        }
        let deck = HangulReadingDeck()
        let expected: [Stage: Int] = [.basicVowels: 10, .basicConsonants: 10, .aspiratedTense: 9, .complexVowels: 11, .syllables: 140]
        for (stage, n) in expected where deck.prompts(for: stage).count != n {
            errors.append("Hangul stage \(stage.rawValue): \(deck.prompts(for: stage).count) cards, expected \(n)")
        }
        let batchim = deck.prompts(for: .batchim).count
        if !(130...170).contains(batchim) { errors.append("Hangul batchim: \(batchim) cards") }
        let all = deck.cards(options: .hangulReading(HangulReadingOptions(stages: Set(Stage.allCases).subtracting([.realWords]))))
        if Set(all.map(\.key)).count != all.count { errors.append("Hangul: duplicate item keys") }
        return errors
    }
}
#endif
