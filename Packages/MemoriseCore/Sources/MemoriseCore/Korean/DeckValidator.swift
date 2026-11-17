/// Validates vocab deck files against the schema rules (§8.2, PLAN_M4 §3.2).
public enum DeckValidator {
    /// `.bundled`: full schema rules. `.user` (M4-8): romanization and `conj` optional, empty deck allowed,
    /// ids must be `user.<8 hex>[.NNNN]`.
    public enum Mode: Sendable { case bundled, user }

    /// Validates one file. Returns human-readable errors (empty = valid).
    public static func validate(_ file: VocabDeckFile, mode: Mode = .bundled) -> [String] {
        var errors: [String] = []
        let prefix = idPrefix(for: file.deckId)
        let user = mode == .user
        if user, !UserDecks.isUserDeckID(DeckID(file.deckId)) { errors.append("\(file.deckId): user deck id must be 'user.<8 hex>'") }
        if user, file.title.isBlank { errors.append("\(file.deckId): title must be non-empty") }
        if !VocabDeckFile.supportedSchemaVersions.contains(file.schemaVersion) {
            errors.append("\(file.deckId): unsupported schemaVersion \(file.schemaVersion)")
        }
        if file.entries.isEmpty, !user { errors.append("\(file.deckId): no entries") }

        var ids = Set<String>()
        var ranks = Set<Int>()
        for e in file.entries {
            let at = "\(file.deckId)/\(e.id)"
            if !ids.insert(e.id).inserted { errors.append("\(at): duplicate id") }
            if !isValidID(e.id, prefix: prefix) { errors.append("\(at): id must be '\(prefix).NNNN'") }
            if e.partOfSpeech == .pattern {
                // Patterns (M4-7): `-`-prefixed or `~` headword, at least 2 examples.
                if !Hangul.isValidPatternHeadword(e.hangul) {
                    errors.append("\(at): pattern '\(e.hangul)' must start with '-' or contain '~'")
                }
                if e.allExamples.count < 2 { errors.append("\(at): patterns need at least 2 examples") }
            } else if !Hangul.isValidHeadword(e.hangul) {
                errors.append("\(at): invalid hangul '\(e.hangul)'")
            }
            if (e.romanization.isEmpty && !user) || e.romanization != e.romanization.lowercased() {
                errors.append("\(at): romanization must be non-empty lowercase")
            }
            if !(1...4).contains(e.meanings.count) || e.meanings.contains(where: { $0.isBlank }) {
                errors.append("\(at): meanings must be 1–4 non-empty glosses")
            }
            if e.partOfSpeech == nil { errors.append("\(at): invalid pos '\(e.pos)'") }
            if (e.partOfSpeech == .verb || e.partOfSpeech == .adjective), !e.hangul.hasSuffix("다") {
                errors.append("\(at): verbs/adjectives must be in dictionary form (-다)")
            }
            if let raw = e.conj, ConjugationClass(rawValue: raw) == nil {
                errors.append("\(at): unknown conj '\(raw)' (read as regular)")
            }
            if e.conj != nil, !(e.partOfSpeech?.isPredicate ?? false) {
                errors.append("\(at): conj is only for verbs/adjectives")
            }
            // Bundled decks: every predicate declares its class (PLAN_M4 §3.2, M4-6).
            if !user, e.partOfSpeech?.isPredicate ?? false, e.conj == nil {
                errors.append("\(at): verbs/adjectives need conj")
            }
            if e.examples.count > 3 { errors.append("\(at): at most 3 examples") }
            for ex in e.examples {
                if ex.ko.isBlank || ex.en.isBlank { errors.append("\(at): examples ko/en must be non-empty") }
                if Hangul.syllableCount(ex.ko) > 40 { errors.append("\(at): example longer than 40 Hangul") }
            }
            if !ranks.insert(e.rank).inserted { errors.append("\(at): duplicate rank \(e.rank)") }
            if let ex = e.example {
                if ex.ko.isBlank || ex.en.isBlank {
                    errors.append("\(at): example ko/en must be non-empty")
                }
                if Hangul.syllableCount(ex.ko) > 40 { errors.append("\(at): example longer than 40 Hangul") }
            }
        }
        if !ranks.isEmpty, ranks != Set(1...file.entries.count) {
            errors.append("\(file.deckId): ranks must be exactly 1…\(file.entries.count)")
        }
        return errors
    }

    /// Validates several files, including cross-file id uniqueness.
    public static func validate(_ files: [VocabDeckFile]) -> [String] {
        var errors = files.flatMap { validate($0) }
        var seen = [String: String]()
        for f in files {
            for e in f.entries {
                if let other = seen[e.id], other != f.deckId {
                    errors.append("\(e.id): id used in both \(other) and \(f.deckId)")
                }
                seen[e.id] = f.deckId
            }
        }
        // M4-1: the same headword + pos in two Core decks (frequency bands must not overlap).
        // Themed decks (AION, patterns) may legitimately repeat a core word.
        var headwords = [String: String]()
        for f in files where f.deckId.hasPrefix("ko.core.") {
            for e in f.entries {
                let key = "\(e.hangul)/\(e.pos)"
                if let other = headwords[key], other != f.deckId {
                    errors.append("\(e.id): '\(e.hangul)' (\(e.pos)) already in \(other)")
                }
                headwords[key] = f.deckId
            }
        }
        return errors
    }

    /// `"ko.core.1"` → `"ko.core"`, `"ko.aion2"` → `"ko.aion2"`.
    static func idPrefix(for deckId: String) -> String {
        guard let dot = deckId.lastIndex(of: "."),
              deckId[deckId.index(after: dot)...].allSatisfy(\.isNumber) else { return deckId }
        return String(deckId[..<dot])
    }

    static func isValidID(_ id: String, prefix: String) -> Bool {
        guard id.hasPrefix(prefix + ".") else { return false }
        let digits = id.dropFirst(prefix.count + 1)
        return digits.count == 4 && digits.allSatisfy(\.isASCII) && digits.allSatisfy(\.isNumber)
    }
}

extension String {
    /// Empty or whitespace only.
    var isBlank: Bool { allSatisfy(\.isWhitespace) }
}
