import Foundation

/// Pure helpers for user-created vocab decks (PLAN_M4 M4-8). Storage lives in the app (`UserDeckStore`).
///
/// Deck ids are `user.<8 hex>`; entry ids `user.<8 hex>.NNNN`. Entry numbers come from
/// `nextEntryNumber`, which only increases, so a deleted entry's id is never reused.
public enum UserDecks {
    public static let prefix = "user."
    /// The auto-created "My AION words" deck (M4-9) — the one user id that isn't hex.
    public static let aionDeckID = "user.aion0001"

    /// `user.` followed by exactly 8 lowercase hex digits, or `aionDeckID`.
    public static func isUserDeckID(_ id: DeckID) -> Bool {
        let raw = id.raw
        if raw == aionDeckID { return true }
        guard raw.hasPrefix(prefix) else { return false }
        let hex = raw.dropFirst(prefix.count)
        return hex.count == 8 && hex.allSatisfy { $0.isHexDigit && !$0.isUppercase }
    }

    /// A fresh deck id not in `existing`.
    public static func newDeckID(existing: Set<String>, using rng: inout SplitMix64) -> String {
        while true {
            let id = prefix + String(format: "%08x", UInt32(truncatingIfNeeded: rng.next()))
            if !existing.contains(id) { return id }
        }
    }

    /// An empty deck.
    public static func newDeck(id: String, title: String, subtitle: String = "") -> VocabDeckFile {
        VocabDeckFile(
            schemaVersion: VocabDeckFile.currentSchemaVersion, deckId: id, title: title, subtitle: subtitle,
            subject: .korean, entries: [], nextEntryNumber: 1
        )
    }

    /// The editable fields of an entry (id and rank are assigned here).
    public struct EntryDraft: Hashable, Sendable {
        public var hangul: String
        /// Comma-separated in the editor; split by `meanings(from:)`.
        public var meanings: [String]
        public var pos: PartOfSpeech
        public var romanization: String
        public var example: VocabEntry.Example?
        public var tags: [String]
        /// "Heard in" references (e.g. a song, M6 lyrics). Not edited in the deck editor; kept on edit.
        public var sources: [MediaRef]

        public init(hangul: String = "", meanings: [String] = [], pos: PartOfSpeech = .noun, romanization: String = "",
                    example: VocabEntry.Example? = nil, tags: [String] = [], sources: [MediaRef] = []) {
            self.hangul = hangul
            self.meanings = meanings
            self.pos = pos
            self.romanization = romanization
            self.example = example
            self.tags = tags
            self.sources = sources
        }

        public init(_ e: VocabEntry) {
            self.init(hangul: e.hangul, meanings: e.meanings, pos: e.partOfSpeech ?? .noun, romanization: e.romanization,
                      example: e.example, tags: e.tags, sources: e.sources)
        }

        /// Trimmed copy (romanization lowercased, empty tags/meanings dropped).
        public var normalized: EntryDraft {
            var d = self
            d.hangul = hangul.trimmingCharacters(in: .whitespacesAndNewlines)
            d.meanings = meanings.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            d.romanization = romanization.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            d.tags = tags.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }.filter { !$0.isEmpty }
            if let ex = example {
                let ko = ex.ko.trimmingCharacters(in: .whitespacesAndNewlines)
                let en = ex.en.trimmingCharacters(in: .whitespacesAndNewlines)
                d.example = ko.isEmpty && en.isEmpty ? nil : VocabEntry.Example(ko: ko, en: en)
            }
            return d
        }

        func entry(id: String, rank: Int) -> VocabEntry {
            let d = normalized
            return VocabEntry(id: id, hangul: d.hangul, romanization: d.romanization, meanings: d.meanings,
                              pos: d.pos.rawValue, rank: rank, tags: d.tags, example: d.example,
                              conj: UserDecks.inferredConj(hangul: d.hangul, pos: d.pos), sources: d.sources)
        }
    }

    /// `conj` for user predicates: only the unambiguous -하다 class is inferred (others read as regular).
    static func inferredConj(hangul: String, pos: PartOfSpeech) -> String? {
        pos.isPredicate && hangul.hasSuffix("하다") && hangul.count >= 3 ? ConjugationClass.ha.rawValue : nil
    }

    /// Part of speech for an imported word (R4-10): a dictionary form (ends in 다) whose first meaning
    /// starts with "to " is a predicate — "to be …" an adjective, otherwise a verb. Everything else is a
    /// noun (바다 "sea" stays a noun because its meaning has no "to").
    public static func guessedPartOfSpeech(hangul: String, meanings: [String]) -> PartOfSpeech {
        let h = hangul.trimmingCharacters(in: .whitespacesAndNewlines)
        guard h.hasSuffix("다"), Hangul.syllableCount(h) >= 2,
              let first = meanings.first?.trimmingCharacters(in: .whitespaces).lowercased(), first.hasPrefix("to ")
        else { return .noun }
        return first.hasPrefix("to be ") ? .adjective : .verb
    }

    /// "a, b ,c" → ["a", "b", "c"].
    public static func meanings(from text: String) -> [String] {
        text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    /// Problems with a draft (empty = OK), using the `.user` validator rules.
    public static func problems(_ draft: EntryDraft, in file: VocabDeckFile) -> [String] {
        let probe = file.deckId + ".0001"
        let test = VocabDeckFile(schemaVersion: file.schemaVersion, deckId: file.deckId, title: file.title.isBlank ? "x" : file.title,
                                 subtitle: file.subtitle, subject: file.subject, entries: [draft.entry(id: probe, rank: 1)])
        return DeckValidator.validate(test, mode: .user).map { $0.replacingOccurrences(of: "\(file.deckId)/\(probe): ", with: "") }
    }

    /// Appends an entry with the next never-used number.
    public static func adding(_ draft: EntryDraft, to file: VocabDeckFile) -> VocabDeckFile {
        let next = max(file.nextEntryNumber ?? 1, (file.entries.compactMap { entryNumber($0.id) }.max() ?? 0) + 1)
        let id = file.deckId + "." + String(format: "%04d", next)
        let entries = file.entries + [draft.entry(id: id, rank: file.entries.count + 1)]
        return replacing(file, entries: entries, nextEntryNumber: next + 1)
    }

    /// Replaces the fields of entry `id` (keeps its id and rank).
    public static func updating(_ id: String, with draft: EntryDraft, in file: VocabDeckFile) -> VocabDeckFile {
        let entries = file.entries.map { $0.id == id ? draft.entry(id: id, rank: $0.rank) : $0 }
        return replacing(file, entries: entries, nextEntryNumber: file.nextEntryNumber)
    }

    /// Removes entry `id`; ranks are re-assigned 1…N, `nextEntryNumber` is kept.
    public static func deleting(_ id: String, from file: VocabDeckFile) -> VocabDeckFile {
        replacing(file, entries: file.entries.filter { $0.id != id }, nextEntryNumber: file.nextEntryNumber)
    }

    /// New title / subtitle.
    public static func renaming(_ file: VocabDeckFile, title: String, subtitle: String) -> VocabDeckFile {
        VocabDeckFile(schemaVersion: file.schemaVersion, deckId: file.deckId,
                      title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                      subtitle: subtitle.trimmingCharacters(in: .whitespacesAndNewlines),
                      subject: file.subject, entries: file.entries, nextEntryNumber: file.nextEntryNumber)
    }

    /// `user.ab12cd34.0007` → 7.
    static func entryNumber(_ id: String) -> Int? {
        guard let dot = id.lastIndex(of: ".") else { return nil }
        return Int(id[id.index(after: dot)...])
    }

    /// Ranks re-assigned 1…N in the current order.
    private static func replacing(_ file: VocabDeckFile, entries: [VocabEntry], nextEntryNumber: Int?) -> VocabDeckFile {
        let ranked = entries.sorted { $0.rank < $1.rank }.enumerated().map { i, e in
            e.rank == i + 1 ? e : VocabEntry(id: e.id, hangul: e.hangul, romanization: e.romanization, meanings: e.meanings,
                                             pos: e.pos, rank: i + 1, tags: e.tags, hanja: e.hanja, example: e.example,
                                             notes: e.notes, conj: e.conj, examples: e.examples,
                                             register: e.register, dialogue: e.dialogue, sources: e.sources)
        }
        return VocabDeckFile(schemaVersion: VocabDeckFile.currentSchemaVersion, deckId: file.deckId, title: file.title,
                             subtitle: file.subtitle, subject: file.subject, entries: ranked, nextEntryNumber: nextEntryNumber)
    }
}

#if DEBUG
public extension UserDecks {
    /// Id rules (M4-8 accept: a deleted number is never reused). Returns errors (empty = OK).
    static func selfCheck() -> [String] {
        var errors: [String] = []
        var rng = SplitMix64(seed: 1)
        let id = newDeckID(existing: [], using: &rng)
        if !isUserDeckID(DeckID(id)) { errors.append("UserDecks: bad deck id \(id)") }
        var f = newDeck(id: id, title: "Test")
        let word = EntryDraft(hangul: "사과", meanings: ["apple"])
        f = adding(word, to: f)
        f = adding(word, to: f)
        f = deleting(id + ".0002", from: f)
        f = adding(word, to: f)
        if f.entries.map(\.id) != [id + ".0001", id + ".0003"] { errors.append("UserDecks: ids \(f.entries.map(\.id))") }
        if f.entries.map(\.rank) != [1, 2] { errors.append("UserDecks: ranks \(f.entries.map(\.rank))") }
        let v = DeckValidator.validate(f, mode: .user)
        if !v.isEmpty { errors.append("UserDecks: validator \(v)") }
        if problems(EntryDraft(hangul: "abc", meanings: []), in: f).isEmpty { errors.append("UserDecks: bad draft accepted") }
        return errors
    }
}
#endif
