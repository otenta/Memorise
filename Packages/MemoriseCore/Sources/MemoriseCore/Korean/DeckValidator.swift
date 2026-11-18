import Foundation

/// Validates vocab deck files against the schema rules (§8.2, PLAN_M4 §3.2, PLAN_M5 §3).
public enum DeckValidator {
    /// `.bundled`: full schema rules. `.user` (M4-8): romanization and `conj` optional, empty deck allowed,
    /// ids must be `user.<8 hex>[.NNNN]`.
    public enum Mode: Sendable { case bundled, user }

    /// Longest example sentence (Hangul syllables) in bundled decks.
    public static let bundledExampleMaxHangul = 40
    /// Longest example sentence in user decks (M6 L8b: a saved lyric line may be long).
    public static let userExampleMaxHangul = 80

    /// Bundled: both lines required, ≤ 40 Hangul. User (L-D10): `ko` required, `en` may be blank, ≤ 80 Hangul,
    /// except pattern entries, whose prompt is the first example's English.
    static func exampleErrors(_ ex: VocabEntry.Example, at: String, plural: Bool, user: Bool, isPattern: Bool) -> [String] {
        var errors: [String] = []
        let subject = plural ? "examples" : "example"
        if user, !isPattern {
            if ex.ko.isBlank { errors.append("\(at): example Korean must be non-empty") }
        } else if ex.ko.isBlank || ex.en.isBlank {
            errors.append("\(at): \(subject) ko/en must be non-empty")
        }
        let limit = user ? userExampleMaxHangul : bundledExampleMaxHangul
        if Hangul.syllableCount(ex.ko) > limit { errors.append("\(at): example longer than \(limit) Hangul") }
        return errors
    }

    /// Validates one file. Returns human-readable errors (empty = valid).
    /// `currentYear` bounds `MediaRef.year` (injected; defaults to the system calendar).
    public static func validate(_ file: VocabDeckFile, mode: Mode = .bundled, currentYear: Int = defaultCurrentYear()) -> [String] {
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
            } else if file.schemaVersion >= 2, e.partOfSpeech == .expression {
                // v2: expressions may carry ? ! , . … (진짜?, 잠깐만!).
                if !Hangul.isValidExpressionHeadword(e.hangul) { errors.append("\(at): invalid hangul '\(e.hangul)'") }
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
            // 러-irregular isn't modelled yet (R4-11): keep those headwords out of the conjugation deck.
            if !user, Conjugator.isUnmodelledReoIrregular(e) {
                errors.append("\(at): 러-irregular (\(e.hangul) → …르러요) isn't supported by the conjugator yet")
            }
            if e.examples.count > 3 { errors.append("\(at): at most 3 examples") }
            for ex in e.examples {
                errors += exampleErrors(ex, at: at, plural: true, user: user, isPattern: e.partOfSpeech == .pattern)
            }
            errors += mediaErrors(e, at: at, mode: mode, currentYear: currentYear)
            if !ranks.insert(e.rank).inserted { errors.append("\(at): duplicate rank \(e.rank)") }
            if let ex = e.example {
                errors += exampleErrors(ex, at: at, plural: false, user: user, isPattern: e.partOfSpeech == .pattern)
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

    /// Ownership key of a headword (R7-F7): NFC Hangul without trailing `?!.~`, plus the part of speech.
    static func headwordKey(_ e: VocabEntry) -> String {
        normalizedHeadword(e) + "\u{1F}" + e.pos
    }

    /// NFC Hangul without surrounding spaces or trailing `?!.~`.
    static func normalizedHeadword(_ e: VocabEntry) -> String {
        var h = e.hangul.precomposedStringWithCanonicalMapping.trimmingCharacters(in: .whitespaces)
        while let last = h.last, "?!.~".contains(last) { h.removeLast() }
        return h
    }

    /// Content overlap across Korean decks (R7-F7), as warnings (never errors):
    /// - every headword in more than one place (all `ko.*` decks, and repeats inside a deck; grouped
    ///   by Hangul, so same-spelling words of different parts of speech are listed too), noting the
    ///   part of speech and which entries are hidden;
    /// - every first gloss (case-insensitive) shared by two or more decks among visible entries.
    ///
    /// `hidden`: entry ids hidden per deck id (see `DeckCatalog.hiddenDuplicates`).
    public static func overlapWarnings(_ files: [VocabDeckFile], hidden: [String: Set<String>] = [:]) -> [String] {
        let korean = files.filter { $0.subject == .korean && $0.deckId.hasPrefix("ko.") }
        var warnings: [String] = []

        var byHeadword: [String: [(deck: String, id: String, pos: String)]] = [:]
        var headwordOrder: [String] = []
        for f in korean {
            for e in f.entries {
                let key = normalizedHeadword(e)
                if byHeadword[key] == nil { headwordOrder.append(key) }
                byHeadword[key, default: []].append((f.deckId, e.id, e.pos))
            }
        }
        for key in headwordOrder {
            guard let uses = byHeadword[key], uses.count > 1 else { continue }
            let list = uses.map { u in
                "\(u.id) \(u.pos)" + ((hidden[u.deck]?.contains(u.id) ?? false) ? " (hidden)" : "")
            }.joined(separator: ", ")
            let sameDeck = Set(uses.map(\.deck)).count == 1
            warnings.append("Duplicate headword '\(key)'\(sameDeck ? " inside one deck" : ""): \(list)")
        }

        var byGloss: [String: [(deck: String, id: String)]] = [:]
        var glossOrder: [String] = []
        for f in korean {
            for e in f.entries where !(hidden[f.deckId]?.contains(e.id) ?? false) {
                guard let first = e.meanings.first else { continue }
                let gloss = first.trimmingCharacters(in: .whitespaces).lowercased()
                if byGloss[gloss] == nil { glossOrder.append(gloss) }
                byGloss[gloss, default: []].append((f.deckId, e.id))
            }
        }
        var sharedGlosses = 0
        for gloss in glossOrder {
            guard let uses = byGloss[gloss], Set(uses.map(\.deck)).count > 1 else { continue }
            sharedGlosses += 1
            warnings.append("Shared first gloss '\(gloss)': \(uses.map(\.id).joined(separator: ", "))")
        }
        if sharedGlosses > 0 { warnings.append("\(sharedGlosses) first glosses are shared across Korean decks") }
        return warnings
    }

    /// Dialogue and media-reference rules (PLAN_M5 §3, K1).
    static func mediaErrors(_ e: VocabEntry, at: String, mode: Mode, currentYear: Int) -> [String] {
        var errors: [String] = []
        if !e.dialogue.isEmpty {
            if !(2...4).contains(e.dialogue.count) { errors.append("\(at): dialogue must have 2–4 lines") }
            for (i, line) in e.dialogue.enumerated() {
                let l = "\(at): dialogue line \(i + 1)"
                if !DialogueLine.speakers.contains(line.speaker) { errors.append("\(l): speaker must be A, B or C") }
                if line.ko.isBlank || line.en.isBlank { errors.append("\(l): ko/en must be non-empty") }
                if Hangul.syllableCount(line.ko) > 40 { errors.append("\(l): longer than 40 Hangul") }
            }
            let phrase = Hangul.matchKey(e.hangul)
            if !phrase.isEmpty, !e.dialogue.contains(where: { Hangul.matchKey($0.ko).contains(phrase) }) {
                errors.append("\(at): dialogue must contain '\(e.hangul)'")
            }
        }
        if e.droppedSourceCount > 0 {
            errors.append("\(at): \(e.droppedSourceCount) source(s) dropped (unknown or missing kind)")
        }
        if e.sources.count > 3 { errors.append("\(at): at most 3 sources") }
        for (i, ref) in e.sources.enumerated() {
            let s = "\(at): source \(i + 1)"
            if ref.title.isBlank || ref.by.isBlank { errors.append("\(s): title and by must be non-empty") }
            if let ko = ref.titleKo, ko.isBlank { errors.append("\(s): titleKo must be non-empty when present") }
            if !(1990...currentYear).contains(ref.year) { errors.append("\(s): year must be 1990…\(currentYear)") }
            if ref.locator.isBlank { errors.append("\(s): locator must be non-empty") }
            if ref.context.isBlank || ref.context.count > 200 { errors.append("\(s): context must be 1–200 characters") }
            if mode == .bundled, !isValidCitation(ref.citation) {
                errors.append("\(s): citation must be an https URL or \"owner\"")
            }
            if ref.hadURLKey { errors.append("\(s): 'url' is not allowed (references are names only)") }
        }
        return errors
    }

    /// An `https` URL with a host, or the literal `"owner"`.
    static func isValidCitation(_ citation: String) -> Bool {
        if citation == "owner" { return true }
        guard let url = URL(string: citation), url.scheme == "https", let host = url.host, !host.isEmpty else { return false }
        return true
    }

    /// Current Gregorian year — the injected default for `validate(_:mode:currentYear:)`.
    public static func defaultCurrentYear() -> Int {
        Calendar(identifier: .gregorian).component(.year, from: Date())
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
