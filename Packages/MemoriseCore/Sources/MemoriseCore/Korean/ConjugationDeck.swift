/// Options for `ko.conjugation` (PLAN_M4 M4-6).
public struct ConjugationOptions: Hashable, Codable, Sendable {
    public enum Source: String, Codable, Sendable, CaseIterable, Hashable {
        /// Raw values are persisted — never change them.
        case allCore, core1

        public var title: String {
            switch self {
            case .allCore: "All Core decks"
            case .core1: "Core 1 only"
            }
        }
    }

    public var forms: Set<ConjForm>
    public var source: Source
    /// Unseen cards introduced per session (in word-rank order).
    public var newPerSession: Int

    public init(forms: Set<ConjForm> = Set(ConjForm.allCases), source: Source = .allCore, newPerSession: Int = 5) {
        self.forms = forms
        self.source = source
        self.newPerSession = newPerSession
    }

    private enum CodingKeys: String, CodingKey { case forms, source, newPerSession }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = ConjugationOptions()
        let decoded = c.tolerant(Set<ConjForm>.self, .forms, d.forms)
        forms = decoded.isEmpty ? d.forms : decoded
        source = c.tolerant(Source.self, .source, d.source)
        newPerSession = max(0, c.tolerant(Int.self, .newPerSession, d.newPerSession))
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(sortedRaw(forms), forKey: .forms)
        try c.encode(newPerSession, forKey: .newPerSession)
        try c.encode(source, forKey: .source)
    }
}

/// "가다 · past polite" → 갔어요.
public struct ConjugationPrompt: Hashable, Sendable {
    public let entry: VocabEntry
    public let form: ConjForm
    public let answer: String
    /// Other accepted spellings (R4-3): 공부하지 않아요 for 공부 안 해요, 보아요 for 봐요. Not displayed.
    public let alternates: [String]
    /// One-line rule, e.g. "ㅏ/ㅗ stem → 았어요, 가+았 → 갔".
    public let rule: String
    /// Introduction order (word rank, then form).
    public let rank: Int

    public init(entry: VocabEntry, form: ConjForm, answer: String, alternates: [String] = [], rule: String, rank: Int) {
        self.entry = entry
        self.form = form
        self.answer = answer
        self.alternates = alternates
        self.rule = rule
        self.rank = rank
    }

    /// Every accepted answer; the first is the displayed one.
    public var acceptedAnswers: [String] { [answer] + alternates }
}

/// `ko.conjugation` — one card per (verb/adjective, form), generated from the Core decks.
public struct ConjugationDeck: Deck {
    public static let deckID: DeckID = "ko.conjugation"

    public let id: DeckID = ConjugationDeck.deckID
    public let kind = DeckKind.koreanConjugation
    public let title = "Conjugation"
    public let subtitle = "가다 → 가요"
    public let subject = Subject.korean
    /// Core verbs/adjectives, deduplicated by spelling (the earliest Core deck keeps a word), in
    /// `.allCore` introduction order: interleaved across Core decks (R7-F7).
    public let predicates: [(entry: VocabEntry, isCore1: Bool)]
    /// Core 1 predicates in rank order, for `.core1` (the owner asked for Core 1 order there).
    private let core1Predicates: [VocabEntry]

    public init(vocab: [VocabDeck] = []) {
        let core = vocab
            .filter { $0.subject == .korean && $0.id.raw.hasPrefix(Self.corePrefix) }
            .sorted { Self.coreNumber($0.id) < Self.coreNumber($1.id) }
        var seen = Set<String>()
        var groups: [(sourceID: String, items: [(entry: VocabEntry, isCore1: Bool)])] = []
        for deck in core {
            let isCore1 = deck.id.raw == "ko.core.1"
            let items = deck.entries.sorted(by: { $0.rank < $1.rank })
                .filter { ($0.partOfSpeech?.isPredicate ?? false) && seen.insert($0.hangul).inserted }
                .map { (entry: $0, isCore1: isCore1) }
            groups.append((deck.id.raw, items))
        }
        core1Predicates = groups.first { $0.sourceID == "ko.core.1" }?.items.map(\.entry) ?? []
        predicates = DerivedIntroductionOrder.interleave(groups, derivedID: Self.deckID)
    }

    static let corePrefix = "ko.core."

    static func coreNumber(_ id: DeckID) -> Int {
        Int(id.raw.dropFirst(corePrefix.count)) ?? .max
    }

    public var defaultOptions: DeckOptions { .conjugation(ConjugationOptions()) }

    public static func itemKey(entryID: String, _ form: ConjForm) -> ItemKey {
        ItemKey("conj:\(entryID):\(form.rawValue)")
    }

    public func cards(options: DeckOptions) -> [Card] {
        guard case let .conjugation(o) = options else { return [] }
        var result: [Card] = []
        let ordered = o.source == .core1 ? core1Predicates : predicates.map(\.entry)
        for (index, entry) in ordered.enumerated() {
            for (formIndex, form) in ConjForm.allCases.enumerated() where o.forms.contains(form) {
                guard let c = Conjugator.conjugate(entry, form) else { continue }
                let prompt = ConjugationPrompt(entry: entry, form: form, answer: c.text, alternates: c.alternates, rule: c.rule,
                                               rank: index * ConjForm.allCases.count + formIndex)
                result.append(Card(key: Self.itemKey(entryID: entry.id, form), deckID: id, content: .conjugation(prompt)))
            }
        }
        return result
    }

    public func introductionRank(of card: Card) -> Int? { card.conjugation?.rank }

    public func newPerSession(options: DeckOptions) -> Int? { options.conjugation?.newPerSession }

    /// Same word ×0.4; same form ×0.7.
    public func patternPenalty(candidate: Card, recent: ArraySlice<Card>) -> Double {
        guard let c = candidate.conjugation, let p = recent.back(0)?.conjugation else { return 1 }
        var penalty = 1.0
        if c.entry.id == p.entry.id { penalty *= 0.4 }
        if c.form == p.form { penalty *= 0.7 }
        return penalty
    }
}

#if DEBUG
public extension ConjugationDeck {
    /// Reference rows (mirrors `docs/conjugation-reference.md`). Returns errors (empty = OK).
    static func selfCheck() -> [String] {
        var errors: [String] = []
        for row in referenceForms {
            let got = Conjugator.conjugate(row.word, class: row.cls, form: row.form, isAdjective: row.adjective)?.text
            if got != row.expected {
                errors.append("Conjugation: \(row.word) \(row.form.rawValue) → \(got ?? "nil"), expected \(row.expected ?? "nil")")
            }
        }
        return errors
    }

    typealias ReferenceRow = (word: String, cls: ConjugationClass, adjective: Bool, form: ConjForm, expected: String?)

    /// Every class × every form, plus the 마시다/되다/주다/오다 contractions.
    static let referenceForms: [ReferenceRow] = {
        func all(_ w: String, _ c: ConjugationClass, adj: Bool = false, _ forms: [String?]) -> [ReferenceRow] {
            zip(ConjForm.allCases, forms).map { (w, c, adj, $0.0, $0.1) }
        }
        // Order: presentPolite, pastPolite, futurePolite, presentCasual, presentFormal, negativePolite, wantTo.
        return all("가다", .regular, ["가요", "갔어요", "갈 거예요", "가", "갑니다", "안 가요", "가고 싶어요"])
            + all("먹다", .regular, ["먹어요", "먹었어요", "먹을 거예요", "먹어", "먹습니다", "안 먹어요", "먹고 싶어요"])
            + all("오다", .regular, ["와요", "왔어요", "올 거예요", "와", "옵니다", "안 와요", "오고 싶어요"])
            + all("마시다", .regular, ["마셔요", "마셨어요", "마실 거예요", "마셔", "마십니다", "안 마셔요", "마시고 싶어요"])
            + all("되다", .regular, ["돼요", "됐어요", "될 거예요", "돼", "됩니다", "안 돼요", "되고 싶어요"])
            + all("주다", .regular, ["줘요", "줬어요", "줄 거예요", "줘", "줍니다", "안 줘요", "주고 싶어요"])
            + all("좋다", .regular, adj: true, ["좋아요", "좋았어요", "좋을 거예요", "좋아", "좋습니다", "안 좋아요", nil])
            + all("하다", .ha, ["해요", "했어요", "할 거예요", "해", "합니다", "안 해요", "하고 싶어요"])
            + all("공부하다", .ha, ["공부해요", "공부했어요", "공부할 거예요", "공부해", "공부합니다", "공부 안 해요", "공부하고 싶어요"])
            + all("필요하다", .ha, adj: true, ["필요해요", "필요했어요", "필요할 거예요", "필요해", "필요합니다", "안 필요해요", nil])
            + all("듣다", .d, ["들어요", "들었어요", "들을 거예요", "들어", "듣습니다", "안 들어요", "듣고 싶어요"])
            + all("돕다", .b, ["도와요", "도왔어요", "도울 거예요", "도와", "돕습니다", "안 도와요", "돕고 싶어요"])
            + all("춥다", .b, adj: true, ["추워요", "추웠어요", "추울 거예요", "추워", "춥습니다", "안 추워요", nil])
            + all("낫다", .s, ["나아요", "나았어요", "나을 거예요", "나아", "낫습니다", "안 나아요", "낫고 싶어요"])
            + all("모르다", .reu, ["몰라요", "몰랐어요", "모를 거예요", "몰라", "모릅니다", nil, nil])
            + all("부르다", .reu, ["불러요", "불렀어요", "부를 거예요", "불러", "부릅니다", "안 불러요", "부르고 싶어요"])
            + all("쓰다", .eu, ["써요", "썼어요", "쓸 거예요", "써", "씁니다", "안 써요", "쓰고 싶어요"])
            + all("바쁘다", .eu, adj: true, ["바빠요", "바빴어요", "바쁠 거예요", "바빠", "바쁩니다", "안 바빠요", nil])
            + all("살다", .l, ["살아요", "살았어요", "살 거예요", "살아", "삽니다", "안 살아요", "살고 싶어요"])
            + all("만들다", .l, ["만들어요", "만들었어요", "만들 거예요", "만들어", "만듭니다", "안 만들어요", "만들고 싶어요"])
            + all("그렇다", .h, adj: true, ["그래요", "그랬어요", "그럴 거예요", "그래", "그렇습니다", "안 그래요", nil])
            + all("이다", .copula, ["이에요", "이었어요", "일 거예요", "이야", "입니다", "아니에요", nil])
            + [
                ("있다", .regular, false, .negativePolite, "없어요"),
                ("맛있다", .regular, true, .negativePolite, "맛없어요"),
                ("알다", .l, false, .negativePolite, "몰라요"),
                ("없다", .regular, true, .negativePolite, nil),
                ("좋아하다", .ha, false, .negativePolite, "안 좋아해요"),
                ("걷다", .d, false, .presentPolite, "걸어요"),
                ("닫다", .regular, false, .presentPolite, "닫아요"),
                ("어렵다", .b, true, .presentPolite, "어려워요"),
                ("새롭다", .b, true, .presentPolite, "새로워요"),
                ("짓다", .s, false, .presentPolite, "지어요"),
                ("빠르다", .reu, true, .presentPolite, "빨라요"),
                ("다르다", .reu, true, .presentPolite, "달라요"),
                ("크다", .eu, true, .presentPolite, "커요"),
                ("예쁘다", .eu, true, .presentPolite, "예뻐요"),
                ("아프다", .eu, true, .presentPolite, "아파요"),
                ("길다", .l, true, .presentFormal, "깁니다"),
                ("열다", .l, false, .presentFormal, "엽니다"),
                ("빨갛다", .h, true, .presentPolite, "빨개요"),
                ("하얗다", .h, true, .presentPolite, "하얘요"),
                ("보내다", .regular, false, .pastPolite, "보냈어요"),
                ("서다", .regular, false, .presentPolite, "서요"),
                ("배우다", .regular, false, .presentPolite, "배워요"),
                ("기다리다", .regular, false, .pastPolite, "기다렸어요"),
                ("있다", .regular, false, .presentFormal, "있습니다"),
            ]
    }()
}
#endif
