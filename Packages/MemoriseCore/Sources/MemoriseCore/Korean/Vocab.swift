/// Direction a vocab card is asked in. Raw values are part of `ItemKey`s — never change.
public enum VocabDirection: String, Codable, Sendable, CaseIterable {
    /// Recognition: Hangul → meaning.
    case koToEn = "ko-en"
    /// Production: meaning → Hangul.
    case enToKo = "en-ko"
}

/// Part of speech values allowed by schema v1.
public enum PartOfSpeech: String, Codable, Sendable, CaseIterable {
    case noun, pronoun, verb, adjective, adverb, particle, determiner, numeral
    case interjection, expression, counter, suffix
}

/// One vocabulary entry (schema v1).
public struct VocabEntry: Hashable, Codable, Sendable, Identifiable {
    public struct Example: Hashable, Codable, Sendable {
        public let ko: String
        public let en: String

        public init(ko: String, en: String) {
            self.ko = ko
            self.en = en
        }
    }

    /// Globally unique, never reused: `<deck-prefix>.<4 digits>`.
    public let id: String
    public let hangul: String
    /// Revised Romanization, lowercase.
    public let romanization: String
    /// 1–4 glosses, most common first.
    public let meanings: [String]
    /// Raw part of speech (validated against `PartOfSpeech`).
    public let pos: String
    /// Introduction order within the file (1…N).
    public let rank: Int
    public let tags: [String]
    public let hanja: String?
    public let example: Example?
    public let notes: String?

    public init(
        id: String, hangul: String, romanization: String, meanings: [String], pos: String, rank: Int,
        tags: [String] = [], hanja: String? = nil, example: Example? = nil, notes: String? = nil
    ) {
        self.id = id
        self.hangul = hangul
        self.romanization = romanization
        self.meanings = meanings
        self.pos = pos
        self.rank = rank
        self.tags = tags
        self.hanja = hanja
        self.example = example
        self.notes = notes
    }

    private enum CodingKeys: String, CodingKey {
        case id, hangul, romanization, meanings, pos, rank, tags, hanja, example, notes
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        hangul = try c.decode(String.self, forKey: .hangul)
        romanization = try c.decode(String.self, forKey: .romanization)
        meanings = try c.decode([String].self, forKey: .meanings)
        pos = try c.decode(String.self, forKey: .pos)
        rank = try c.decode(Int.self, forKey: .rank)
        tags = try c.decodeIfPresent([String].self, forKey: .tags) ?? []
        hanja = try c.decodeIfPresent(String.self, forKey: .hanja)
        example = try c.decodeIfPresent(Example.self, forKey: .example)
        notes = try c.decodeIfPresent(String.self, forKey: .notes)
    }

    public var partOfSpeech: PartOfSpeech? { PartOfSpeech(rawValue: pos) }

    /// Meanings joined for display: "I, me".
    public var meaningText: String { meanings.joined(separator: ", ") }
}

/// On-disk deck file (schema v1).
public struct VocabDeckFile: Codable, Sendable, Hashable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let deckId: String
    public let title: String
    public let subtitle: String
    public let subject: Subject
    public let entries: [VocabEntry]

    public init(schemaVersion: Int = 1, deckId: String, title: String, subtitle: String, subject: Subject, entries: [VocabEntry]) {
        self.schemaVersion = schemaVersion
        self.deckId = deckId
        self.title = title
        self.subtitle = subtitle
        self.subject = subject
        self.entries = entries
    }
}

/// Options for vocab decks.
public struct VocabOptions: Hashable, Codable, Sendable {
    public enum DirectionOption: String, Codable, Sendable, CaseIterable {
        case koToEn, enToKo, both

        public var directions: [VocabDirection] {
            switch self {
            case .koToEn: [.koToEn]
            case .enToKo: [.enToKo]
            case .both: [.koToEn, .enToKo]
            }
        }
    }

    public var direction: DirectionOption
    /// How many unseen entries may be introduced per session.
    public var newPerSession: Int
    public var autoPlayAudio: Bool
    /// Empty = all tags.
    public var tags: Set<String>

    public init(direction: DirectionOption = .koToEn, newPerSession: Int = 10, autoPlayAudio: Bool = true, tags: Set<String> = []) {
        self.direction = direction
        self.newPerSession = newPerSession
        self.autoPlayAudio = autoPlayAudio
        self.tags = tags
    }

    private enum CodingKeys: String, CodingKey {
        case direction, newPerSession, autoPlayAudio, tags
    }

    /// Tolerant decoding: every property falls back to its default when missing or unreadable.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = VocabOptions()
        direction = (try? c.decodeIfPresent(DirectionOption.self, forKey: .direction)) ?? d.direction
        newPerSession = (try? c.decodeIfPresent(Int.self, forKey: .newPerSession)) ?? d.newPerSession
        autoPlayAudio = (try? c.decodeIfPresent(Bool.self, forKey: .autoPlayAudio)) ?? d.autoPlayAudio
        tags = (try? c.decodeIfPresent(Set<String>.self, forKey: .tags)) ?? d.tags
    }

    /// Same keys as the synthesised format; `tags` is written sorted for deterministic output.
    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(direction, forKey: .direction)
        try c.encode(newPerSession, forKey: .newPerSession)
        try c.encode(autoPlayAudio, forKey: .autoPlayAudio)
        try c.encode(tags.sorted(), forKey: .tags)
    }

    /// Drops tags the deck no longer has (stale saved filters).
    public func sanitized(allTags: some Sequence<String>) -> VocabOptions {
        var o = self
        o.tags.formIntersection(allTags)
        return o
    }
}

/// Hangul helpers.
public enum Hangul {
    /// Precomposed Hangul syllable block (U+AC00–U+D7A3).
    @inlinable public static func isSyllable(_ s: Unicode.Scalar) -> Bool {
        (0xAC00...0xD7A3).contains(s.value)
    }

    /// Only syllables, spaces, `~` and `-`, with at least one syllable.
    public static func isValidHeadword(_ text: String) -> Bool {
        var sawSyllable = false
        for s in text.unicodeScalars {
            if isSyllable(s) { sawSyllable = true; continue }
            if s == " " || s == "~" || s == "-" { continue }
            return false
        }
        return sawSyllable
    }

    /// Number of Hangul syllables in `text`.
    public static func syllableCount(_ text: String) -> Int {
        text.unicodeScalars.reduce(0) { $0 + (isSyllable($1) ? 1 : 0) }
    }
}
