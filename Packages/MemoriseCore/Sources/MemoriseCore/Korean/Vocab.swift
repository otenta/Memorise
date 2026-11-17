import Foundation

/// Direction a vocab card is asked in. Raw values are part of `ItemKey`s — never change.
public enum VocabDirection: String, Codable, Sendable, CaseIterable {
    /// Recognition: Hangul → meaning.
    case koToEn = "ko-en"
    /// Production: meaning → Hangul.
    case enToKo = "en-ko"
    /// Listening: TTS plays the Hangul, recall the meaning (separate stats from ko→en).
    case listen = "listen"

    /// Short label: "KO→EN", "EN→KO", "🔊".
    public var shortLabel: String {
        switch self {
        case .koToEn: "KO→EN"
        case .enToKo: "EN→KO"
        case .listen: "🔊"
        }
    }
}

/// Part of speech values allowed by the schema. Raw values are persisted — additive only.
public enum PartOfSpeech: String, Codable, Sendable, CaseIterable {
    case noun, pronoun, verb, adjective, adverb, particle, determiner, numeral
    case interjection, expression, counter, suffix
    /// Grammar pattern (`-고 싶다`), schema v2.
    case pattern

    /// Verbs and adjectives conjugate.
    public var isPredicate: Bool { self == .verb || self == .adjective }
}

/// Irregular conjugation class of a verb/adjective (schema v2 `conj`). Raw values are persisted.
public enum ConjugationClass: String, Codable, Sendable, CaseIterable {
    case regular
    /// -하다 (하 → 해).
    case ha
    /// ㅂ-irregular (ㅂ → 우; 돕다/곱다 → 와).
    case b
    /// ㄷ-irregular (ㄷ → ㄹ before a vowel).
    case d
    /// ㅅ-irregular (ㅅ drops before a vowel).
    case s
    /// 르-irregular (르 → ㄹ라/ㄹ러).
    case reu
    /// ㅡ-drop.
    case eu
    /// ㄹ-drop before ㄴ/ㅂ/ㅅ.
    case l
    /// ㅎ-irregular adjectives (그렇다 → 그래요).
    case h
    /// 이다.
    case copula
}

/// Speech level of a phrase (schema v2, PLAN_M5 §3). Raw values are persisted — additive only.
public enum Register: String, Codable, Sendable, CaseIterable {
    case casual, polite, formal
}

/// One line of an original mini-dialogue (schema v2, PLAN_M5 §3). `speaker` is "A", "B" or "C".
public struct DialogueLine: Hashable, Codable, Sendable {
    public static let speakers: Set<String> = ["A", "B", "C"]

    public let speaker: String
    public let ko: String
    public let en: String

    public init(speaker: String, ko: String, en: String) {
        self.speaker = speaker
        self.ko = ko
        self.en = en
    }

    private enum CodingKeys: String, CodingKey { case speaker, ko, en }

    /// Tolerant: missing fields decode as empty strings, which the validator reports.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        speaker = (try? c.decodeIfPresent(String.self, forKey: .speaker)) ?? ""
        ko = (try? c.decodeIfPresent(String.self, forKey: .ko)) ?? ""
        en = (try? c.decodeIfPresent(String.self, forKey: .en)) ?? ""
    }
}

/// A verified media reference for a phrase (schema v2, PLAN_M5 §3). Names only — never a link.
public struct MediaRef: Hashable, Codable, Sendable {
    /// Raw values are persisted — additive only.
    public enum Kind: String, Codable, Sendable, CaseIterable {
        case song, drama
        /// Variety / reality programme.
        case show
        case film
    }

    public let kind: Kind
    public let title: String
    public let titleKo: String?
    /// Artist (songs) or broadcaster/network (screen).
    public let by: String
    public let year: Int
    /// "chorus", "verse 1", "S1 E4", …
    public let locator: String
    /// Original 1–2 sentence description of the moment (≤ 200 chars).
    public let context: String
    /// `https` URL used to verify, or `"owner"`. Never shown in the UI outside DEBUG.
    public let citation: String
    /// The file had a `url` key (forbidden: no-links rule). Decoded only, never encoded.
    public let hadURLKey: Bool

    public init(
        kind: Kind, title: String, titleKo: String? = nil, by: String, year: Int, locator: String,
        context: String, citation: String
    ) {
        self.kind = kind
        self.title = title
        self.titleKo = titleKo
        self.by = by
        self.year = year
        self.locator = locator
        self.context = context
        self.citation = citation
        hadURLKey = false
    }

    private enum CodingKeys: String, CodingKey {
        case kind, title, titleKo, by, year, locator, context, citation
        /// Decoding only, so the validator can flag it.
        case url
    }

    /// Tolerant except for `kind`: an unknown or missing kind throws, and `VocabEntry` drops just this ref.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        kind = try c.decode(Kind.self, forKey: .kind)
        title = (try? c.decodeIfPresent(String.self, forKey: .title)) ?? ""
        titleKo = try? c.decodeIfPresent(String.self, forKey: .titleKo)
        by = (try? c.decodeIfPresent(String.self, forKey: .by)) ?? ""
        year = (try? c.decodeIfPresent(Int.self, forKey: .year)) ?? 0
        locator = (try? c.decodeIfPresent(String.self, forKey: .locator)) ?? ""
        context = (try? c.decodeIfPresent(String.self, forKey: .context)) ?? ""
        citation = (try? c.decodeIfPresent(String.self, forKey: .citation)) ?? ""
        hadURLKey = c.contains(.url)
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(kind, forKey: .kind)
        try c.encode(title, forKey: .title)
        try c.encodeIfPresent(titleKo, forKey: .titleKo)
        try c.encode(by, forKey: .by)
        try c.encode(year, forKey: .year)
        try c.encode(locator, forKey: .locator)
        try c.encode(context, forKey: .context)
        try c.encode(citation, forKey: .citation)
    }
}

/// Decodes one element of an array without failing the whole array.
private struct Lossy<T: Decodable>: Decodable {
    let value: T?
    init(from decoder: any Decoder) throws { value = try? T(from: decoder) }
}

/// One vocabulary entry (schema v1, plus the optional v2 fields `conj`, `examples`, `register`, `dialogue`, `sources`).
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
    /// Raw irregular class (v2). Unknown values are kept here and read as `.regular`.
    public let conj: String?
    /// Up to 3 extra example pairs (v2, patterns deck).
    public let examples: [Example]
    /// Speech level (v2, media deck). Unknown values decode as `nil`.
    public let register: Register?
    /// Original mini-dialogue, 2–4 lines (v2, media deck).
    public let dialogue: [DialogueLine]
    /// Verified media references, 0–3 (v2, media deck).
    public let sources: [MediaRef]
    /// Sources dropped while decoding (unknown `kind`). Not encoded; reported by the validator.
    public let droppedSourceCount: Int

    public init(
        id: String, hangul: String, romanization: String, meanings: [String], pos: String, rank: Int,
        tags: [String] = [], hanja: String? = nil, example: Example? = nil, notes: String? = nil,
        conj: String? = nil, examples: [Example] = [], register: Register? = nil,
        dialogue: [DialogueLine] = [], sources: [MediaRef] = []
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
        self.conj = conj
        self.examples = examples
        self.register = register
        self.dialogue = dialogue
        self.sources = sources
        droppedSourceCount = 0
    }

    private enum CodingKeys: String, CodingKey {
        case id, hangul, romanization, meanings, pos, rank, tags, hanja, example, notes, conj, examples
        case register, dialogue, sources
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        hangul = try c.decode(String.self, forKey: .hangul)
        // Optional in user decks (M4-8); the bundled validator still requires it.
        romanization = try c.decodeIfPresent(String.self, forKey: .romanization) ?? ""
        meanings = try c.decode([String].self, forKey: .meanings)
        pos = try c.decode(String.self, forKey: .pos)
        rank = try c.decode(Int.self, forKey: .rank)
        tags = try c.decodeIfPresent([String].self, forKey: .tags) ?? []
        hanja = try c.decodeIfPresent(String.self, forKey: .hanja)
        example = try c.decodeIfPresent(Example.self, forKey: .example)
        notes = try c.decodeIfPresent(String.self, forKey: .notes)
        conj = try? c.decodeIfPresent(String.self, forKey: .conj)
        examples = (try? c.decodeIfPresent([Example].self, forKey: .examples)) ?? []
        register = try? c.decodeIfPresent(Register.self, forKey: .register)
        dialogue = (try? c.decodeIfPresent([DialogueLine].self, forKey: .dialogue)) ?? []
        let rawSources = (try? c.decodeIfPresent([Lossy<MediaRef>].self, forKey: .sources)) ?? []
        sources = rawSources.compactMap(\.value)
        droppedSourceCount = rawSources.count - sources.count
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(hangul, forKey: .hangul)
        try c.encode(romanization, forKey: .romanization)
        try c.encode(meanings, forKey: .meanings)
        try c.encode(pos, forKey: .pos)
        try c.encode(rank, forKey: .rank)
        try c.encode(tags, forKey: .tags)
        try c.encodeIfPresent(hanja, forKey: .hanja)
        try c.encodeIfPresent(example, forKey: .example)
        try c.encodeIfPresent(notes, forKey: .notes)
        try c.encodeIfPresent(conj, forKey: .conj)
        if !examples.isEmpty { try c.encode(examples, forKey: .examples) }
        try c.encodeIfPresent(register, forKey: .register)
        if !dialogue.isEmpty { try c.encode(dialogue, forKey: .dialogue) }
        if !sources.isEmpty { try c.encode(sources, forKey: .sources) }
    }

    public var partOfSpeech: PartOfSpeech? { PartOfSpeech(rawValue: pos) }

    /// Irregular class for the conjugator (`.regular` when missing or unknown).
    public var conjugationClass: ConjugationClass { conj.flatMap(ConjugationClass.init(rawValue:)) ?? .regular }

    /// `example` followed by `examples`, de-duplicated.
    public var allExamples: [Example] {
        var out: [Example] = []
        for ex in [example].compactMap({ $0 }) + examples where !out.contains(ex) { out.append(ex) }
        return out
    }

    /// Meanings joined for display: "I, me".
    public var meaningText: String { meanings.joined(separator: ", ") }
}

/// On-disk deck file. v2 adds optional entry fields (`conj`, `examples`, pos `pattern`;
/// `register`, `dialogue`, `sources` for the media deck — PLAN_M5 §3);
/// v1 files remain valid.
public struct VocabDeckFile: Codable, Sendable, Hashable {
    public static let currentSchemaVersion = 2
    public static let supportedSchemaVersions = 1...currentSchemaVersion

    public let schemaVersion: Int
    public let deckId: String
    public let title: String
    public let subtitle: String
    public let subject: Subject
    public let entries: [VocabEntry]
    /// User decks (M4-8): the next entry number to assign. Only ever increases, so ids are never reused.
    public let nextEntryNumber: Int?

    public init(
        schemaVersion: Int = 1, deckId: String, title: String, subtitle: String, subject: Subject,
        entries: [VocabEntry], nextEntryNumber: Int? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.deckId = deckId
        self.title = title
        self.subtitle = subtitle
        self.subject = subject
        self.entries = entries
        self.nextEntryNumber = nextEntryNumber
    }

    private enum CodingKeys: String, CodingKey { case schemaVersion, deckId, title, subtitle, subject, entries, nextEntryNumber }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decode(Int.self, forKey: .schemaVersion)
        deckId = try c.decode(String.self, forKey: .deckId)
        title = try c.decode(String.self, forKey: .title)
        subtitle = try c.decodeIfPresent(String.self, forKey: .subtitle) ?? ""
        subject = try c.decode(Subject.self, forKey: .subject)
        entries = try c.decode([VocabEntry].self, forKey: .entries)
        nextEntryNumber = try? c.decodeIfPresent(Int.self, forKey: .nextEntryNumber)
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(schemaVersion, forKey: .schemaVersion)
        try c.encode(deckId, forKey: .deckId)
        try c.encode(title, forKey: .title)
        try c.encode(subtitle, forKey: .subtitle)
        try c.encode(subject, forKey: .subject)
        try c.encode(entries, forKey: .entries)
        try c.encodeIfPresent(nextEntryNumber, forKey: .nextEntryNumber)
    }
}

/// Options for vocab decks.
public struct VocabOptions: Hashable, Codable, Sendable {
    /// Persisted raw values — additive only.
    public enum DirectionOption: String, Codable, Sendable, CaseIterable {
        case koToEn, enToKo, both
        /// TTS → meaning.
        case listening
        /// ko→en + en→ko + listening.
        case allThree

        public var directions: [VocabDirection] {
            switch self {
            case .koToEn: [.koToEn]
            case .enToKo: [.enToKo]
            case .both: [.koToEn, .enToKo]
            case .listening: [.listen]
            case .allThree: [.koToEn, .enToKo, .listen]
            }
        }

        public var includesListening: Bool { directions.contains(.listen) }

        /// The same option without listening (no Korean voice installed).
        public var withoutListening: DirectionOption {
            switch self {
            case .listening: .koToEn
            case .allThree: .both
            default: self
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

    /// Drops listening cards (no Korean voice installed).
    public func withoutListening() -> VocabOptions {
        var o = self
        o.direction = direction.withoutListening
        return o
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

    /// Grammar-pattern headword (`-(으)ㄹ 수 있다`, `-아/어요`, `-(으)ㄹ까요?`): syllables plus compatibility
    /// jamo (U+3131–U+318E), spaces and `~ - ( ) / ?`. Must start with `-` or contain `~` (PLAN_M4 M4-7).
    public static func isValidPatternHeadword(_ text: String) -> Bool {
        guard text.hasPrefix("-") || text.contains("~") else { return false }
        var sawSyllable = false
        for s in text.unicodeScalars {
            if isSyllable(s) { sawSyllable = true; continue }
            if (0x3131...0x318E).contains(s.value) { continue }
            if " ~-()/?".unicodeScalars.contains(s) { continue }
            return false
        }
        return sawSyllable
    }

    /// Expression headword in a v2 file (PLAN_M5 §3): a normal headword that may also contain `? ! , . …`.
    public static func isValidExpressionHeadword(_ text: String) -> Bool {
        let punctuation = "?!,.…".unicodeScalars
        let stripped = String(String.UnicodeScalarView(text.unicodeScalars.filter { !punctuation.contains($0) }))
        return isValidHeadword(stripped)
    }

    /// Text reduced to letters and digits, for punctuation/whitespace-insensitive matching.
    public static func matchKey(_ text: String) -> String {
        String(String.UnicodeScalarView(text.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }))
    }

    /// Number of Hangul syllables in `text`.
    public static func syllableCount(_ text: String) -> Int {
        text.unicodeScalars.reduce(0) { $0 + (isSyllable($1) ? 1 : 0) }
    }
}
