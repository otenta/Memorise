/// A Korean particle with batchim / vowel forms (PLAN_M4 M4-5).
public enum Particle: String, Codable, Sendable, CaseIterable, Hashable {
    /// Raw values are persisted and part of `ItemKey`s — never change them.
    case topic, subject, object, and, direction, copula

    public var title: String {
        switch self {
        case .topic: "topic"
        case .subject: "subject"
        case .object: "object"
        case .and: "and / with"
        case .direction: "direction / means"
        case .copula: "is (copula)"
        }
    }

    /// Both forms, e.g. `은/는`.
    public var pair: String { "\(form(after: .batchim))/\(form(after: .vowel))" }

    /// The form taken after a noun of this ending class.
    public func form(after ending: NounEnding) -> String {
        switch (self, ending) {
        case (.topic, .vowel): "는"
        case (.topic, _): "은"
        case (.subject, .vowel): "가"
        case (.subject, _): "이"
        case (.object, .vowel): "를"
        case (.object, _): "을"
        case (.and, .vowel): "와"
        case (.and, _): "과"
        case (.direction, .batchim): "으로"
        case (.direction, _): "로"
        case (.copula, .vowel): "예요"
        case (.copula, _): "이에요"
        }
    }

    /// The other form (the wrong choice).
    public func wrongForm(after ending: NounEnding) -> String {
        switch ending {
        case .vowel: form(after: .batchim)
        case .batchim: form(after: .vowel)
        // ㄹ + direction: the trap is 으로.
        case .rieul: self == .direction ? "으로" : form(after: .vowel)
        }
    }

    /// Ending classes with their own card (ㄹ only matters for direction).
    public var endings: [NounEnding] {
        self == .direction ? [.batchim, .vowel, .rieul] : [.batchim, .vowel]
    }

    /// "Ends in a consonant → 은".
    public func rule(for ending: NounEnding) -> String {
        switch ending {
        case .batchim: "Ends in a consonant → \(form(after: .batchim))"
        case .vowel: "Ends in a vowel → \(form(after: .vowel))"
        case .rieul: "Ends in ㄹ → 로 (not 으로)"
        }
    }
}

/// How a noun ends, for particle choice.
public enum NounEnding: String, Codable, Sendable, CaseIterable, Hashable {
    /// Raw values are part of `ItemKey`s — never change them.
    case batchim, vowel, rieul

    /// ㄹ final index in `Hangul.finals`.
    static let rieulFinal = 8

    /// Ending class of a word for `particle`: ㄹ-final nouns count as `rieul` only for direction.
    public static func of(_ word: String, for particle: Particle) -> NounEnding? {
        guard let final = Hangul.finalIndex(of: word) else { return nil }
        if final == 0 { return .vowel }
        if final == rieulFinal, particle == .direction { return .rieul }
        return .batchim
    }
}

/// Options for `ko.particles`.
public struct ParticleOptions: Hashable, Codable, Sendable {
    public enum NounSource: String, Codable, Sendable, CaseIterable, Hashable {
        /// Raw values are persisted — never change them.
        case allKorean, coreOnly

        public var title: String {
            switch self {
            case .allKorean: "All Korean decks"
            case .coreOnly: "Core decks only"
            }
        }
    }

    public var particles: Set<Particle>
    public var nounSource: NounSource

    public init(particles: Set<Particle> = Set(Particle.allCases), nounSource: NounSource = .allKorean) {
        self.particles = particles
        self.nounSource = nounSource
    }

    private enum CodingKeys: String, CodingKey { case particles, nounSource }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = ParticleOptions()
        let decoded = c.tolerant(Set<Particle>.self, .particles, d.particles)
        particles = decoded.isEmpty ? d.particles : decoded
        nounSource = c.tolerant(NounSource.self, .nounSource, d.nounSource)
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(nounSource, forKey: .nounSource)
        try c.encode(sortedRaw(particles), forKey: .particles)
    }
}

/// "책 + (topic)" → 책은 / 책는.
public struct ParticlePrompt: Hashable, Sendable {
    public let particle: Particle
    public let ending: NounEnding
    public let noun: VocabEntry

    public init(particle: Particle, ending: NounEnding, noun: VocabEntry) {
        self.particle = particle
        self.ending = ending
        self.noun = noun
    }

    public var correct: String { noun.hangul + particle.form(after: ending) }
    public var wrong: String { noun.hangul + particle.wrongForm(after: ending) }
    public var rule: String { particle.rule(for: ending) }
}

/// `ko.particles` — 13 cards (particle × ending class); `present` picks a fresh noun each time.
public struct ParticlesDeck: Deck {
    public static let deckID: DeckID = "ko.particles"

    public let id: DeckID = ParticlesDeck.deckID
    public let kind = DeckKind.koreanParticles
    public let title = "Particles"
    public let subtitle = "은/는, 이/가, 을/를 …"
    public let subject = Subject.korean
    /// Every usable noun (deduplicated by spelling), with whether it came from a Core deck.
    public let nouns: [(entry: VocabEntry, isCore: Bool)]

    public init(vocab: [VocabDeck] = []) {
        var seen = Set<String>()
        var out: [(VocabEntry, Bool)] = []
        for deck in vocab where deck.subject == .korean {
            let core = deck.id.raw.hasPrefix("ko.core.")
            for e in deck.entries where Self.isUsableNoun(e) && seen.insert(e.hangul).inserted {
                out.append((e, core))
            }
        }
        nouns = out
    }

    /// Plain nouns written only in syllables (pronouns excluded: 내가/제가/네가).
    static func isUsableNoun(_ e: VocabEntry) -> Bool {
        e.partOfSpeech == .noun && Hangul.syllableCount(e.hangul) > 0
            && e.hangul.unicodeScalars.allSatisfy(Hangul.isSyllable)
    }

    public var defaultOptions: DeckOptions { .particles(ParticleOptions()) }

    public static func itemKey(_ particle: Particle, _ ending: NounEnding) -> ItemKey {
        ItemKey("particle:\(particle.rawValue):\(ending.rawValue)")
    }

    /// Nouns of an ending class for `particle` from the configured source (falls back to all decks).
    public func pool(_ particle: Particle, _ ending: NounEnding, source: ParticleOptions.NounSource) -> [VocabEntry] {
        let all = nouns.filter { NounEnding.of($0.entry.hangul, for: particle) == ending }
        let picked = source == .coreOnly ? all.filter(\.isCore) : all
        return (picked.isEmpty ? all : picked).map(\.entry)
    }

    public func cards(options: DeckOptions) -> [Card] {
        guard case let .particles(o) = options else { return [] }
        var result: [Card] = []
        for particle in Particle.allCases where o.particles.contains(particle) {
            for ending in particle.endings {
                guard let noun = pool(particle, ending, source: o.nounSource).first else { continue }
                result.append(Card(key: Self.itemKey(particle, ending), deckID: id,
                                   content: .particle(ParticlePrompt(particle: particle, ending: ending, noun: noun))))
            }
        }
        return result
    }

    /// A random noun of the card's ending class.
    public func present(_ card: Card, options: DeckOptions, using rng: inout SplitMix64) -> Card {
        guard let p = card.particle, let o = options.particles else { return card }
        let pool = pool(p.particle, p.ending, source: o.nounSource)
        guard let noun = pool.randomElement(using: &rng) else { return card }
        return card.with(.particle(ParticlePrompt(particle: p.particle, ending: p.ending, noun: noun)))
    }

    /// Same particle ×0.5; same ending class ×0.8.
    public func patternPenalty(candidate: Card, recent: ArraySlice<Card>) -> Double {
        guard let c = candidate.particle, let p = recent.back(0)?.particle else { return 1 }
        var penalty = 1.0
        if c.particle == p.particle { penalty *= 0.5 }
        if c.ending == p.ending { penalty *= 0.8 }
        return penalty
    }
}

#if DEBUG
public extension ParticlesDeck {
    /// Reference forms (PLAN_M4 M4-5 §5) and card count. Returns errors (empty = OK).
    static func selfCheck() -> [String] {
        var errors: [String] = []
        let reference: [(String, Particle, String)] = [
            ("책", .topic, "책은"), ("학교", .topic, "학교는"), ("물", .direction, "물로"), ("집", .direction, "집으로"),
            ("친구", .copula, "친구예요"), ("사과", .object, "사과를"), ("선생님", .subject, "선생님이"), ("물", .topic, "물은"),
        ]
        for (noun, particle, expected) in reference {
            guard let ending = NounEnding.of(noun, for: particle) else { errors.append("Particles: no ending for \(noun)"); continue }
            let got = noun + particle.form(after: ending)
            if got != expected { errors.append("Particles: \(noun) + \(particle.rawValue) → \(got), expected \(expected)") }
            if noun + particle.wrongForm(after: ending) == expected { errors.append("Particles: wrong form equals answer for \(noun)") }
        }
        let keys = Particle.allCases.flatMap { p in p.endings.map { itemKey(p, $0) } }
        if keys.count != 13 || Set(keys).count != 13 { errors.append("Particles: \(keys.count) card keys, expected 13") }
        return errors
    }
}
#endif
