/// Validates vocab deck files against schema v1 rules (§8.2).
public enum DeckValidator {
    /// Validates one file. Returns human-readable errors (empty = valid).
    public static func validate(_ file: VocabDeckFile) -> [String] {
        var errors: [String] = []
        let prefix = idPrefix(for: file.deckId)
        if file.schemaVersion != VocabDeckFile.currentSchemaVersion {
            errors.append("\(file.deckId): unsupported schemaVersion \(file.schemaVersion)")
        }
        if file.entries.isEmpty { errors.append("\(file.deckId): no entries") }

        var ids = Set<String>()
        var ranks = Set<Int>()
        for e in file.entries {
            let at = "\(file.deckId)/\(e.id)"
            if !ids.insert(e.id).inserted { errors.append("\(at): duplicate id") }
            if !isValidID(e.id, prefix: prefix) { errors.append("\(at): id must be '\(prefix).NNNN'") }
            if !Hangul.isValidHeadword(e.hangul) { errors.append("\(at): invalid hangul '\(e.hangul)'") }
            if e.romanization.isEmpty || e.romanization != e.romanization.lowercased() {
                errors.append("\(at): romanization must be non-empty lowercase")
            }
            if !(1...4).contains(e.meanings.count) || e.meanings.contains(where: { $0.isBlank }) {
                errors.append("\(at): meanings must be 1–4 non-empty glosses")
            }
            if e.partOfSpeech == nil { errors.append("\(at): invalid pos '\(e.pos)'") }
            if (e.partOfSpeech == .verb || e.partOfSpeech == .adjective), !e.hangul.hasSuffix("다") {
                errors.append("\(at): verbs/adjectives must be in dictionary form (-다)")
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
        var errors = files.flatMap(validate)
        var seen = [String: String]()
        for f in files {
            for e in f.entries {
                if let other = seen[e.id], other != f.deckId {
                    errors.append("\(e.id): id used in both \(other) and \(f.deckId)")
                }
                seen[e.id] = f.deckId
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
