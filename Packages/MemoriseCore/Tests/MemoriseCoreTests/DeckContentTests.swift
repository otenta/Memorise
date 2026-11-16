import Testing
@testable import MemoriseCore

/// PLAN §8.2/§8.3 (bundled content + validator), F8 (per-file loading).
@Suite("Deck content & catalog (§8.2, F8)")
struct DeckContentTests {
    static let files = DeckCatalog.bundledVocabFiles.map { try! DeckCatalog.loadBundledVocabFile(named: $0) }

    @Test(arguments: DeckCatalog.bundledVocabFiles)
    func bundledFileIsValid(name: String) throws {
        let file = try DeckCatalog.loadBundledVocabFile(named: name)
        #expect(DeckValidator.validate(file) == [])
    }

    @Test func bundledFilesValidTogetherWithUniqueIDsAcrossFiles() {
        #expect(DeckValidator.validate(Self.files) == [])
        let ids = Self.files.flatMap { $0.entries.map(\.id) }
        #expect(Set(ids).count == ids.count)
    }

    @Test func entryCountsMatchTracker() {
        let byDeck = Dictionary(uniqueKeysWithValues: Self.files.map { ($0.deckId, $0.entries.count) })
        #expect(byDeck["ko.core.1"] == 205)
        #expect(byDeck["ko.aion2"] == 81)
    }

    @Test func verbsAndAdjectivesAreInDictionaryForm() {
        for f in Self.files {
            for e in f.entries where e.partOfSpeech == .verb || e.partOfSpeech == .adjective {
                #expect(e.hangul.hasSuffix("다"), "\(e.id) \(e.hangul)")
            }
        }
    }

    @Test func builtInCatalogLoadsThreeDecksWithoutIssues() {
        let (catalog, issues) = DeckCatalog.builtIn()
        #expect(issues == [])
        #expect(catalog.decks.map(\.id.raw) == ["music.fretboard.notes", "ko.core.1", "ko.aion2"])
        #expect(catalog.deck(id: "ko.aion2")?.title == "Korean · AION 2")
        #expect(catalog.deck(id: "missing") == nil)
        #expect(catalog.decks(for: .korean).count == 2)
        #expect(catalog.decks(for: .music).count == 1)
    }

    @Test func missingFileIsSkippedAndReported() {
        let (catalog, issues) = DeckCatalog.builtIn(files: ["ko_core_1", "does_not_exist"])
        #expect(catalog.decks.map(\.id.raw) == ["music.fretboard.notes", "ko.core.1"])
        #expect(issues.count == 1)
        #expect(issues.first?.hasPrefix("does_not_exist:") == true)
    }

    // MARK: Validator rules on synthetic files

    @Test func validatorAcceptsAMinimalValidFile() {
        #expect(DeckValidator.validate(vocabFile(count: 3)) == [])
    }

    @Test func validatorReportsEveryRule() {
        let bad = VocabDeckFile(
            schemaVersion: 2, deckId: "ko.test.1", title: "T", subtitle: "", subject: .korean,
            entries: [
                VocabEntry(id: "ko.test.0001", hangul: "abc", romanization: "Abc", meanings: [], pos: "thing", rank: 1),
                VocabEntry(id: "ko.test.0001", hangul: "가", romanization: "ga", meanings: ["go"], pos: "verb", rank: 1),
                VocabEntry(id: "ko.other.1", hangul: "나", romanization: "na", meanings: ["a", "b", "c", "d", "e"], pos: "noun", rank: 5,
                           example: VocabEntry.Example(ko: String(repeating: "가", count: 41), en: " ")),
            ]
        )
        let errors = DeckValidator.validate(bad).joined(separator: "\n")
        for fragment in ["unsupported schemaVersion", "duplicate id", "id must be", "invalid hangul", "romanization must be",
                         "meanings must be", "invalid pos", "dictionary form", "duplicate rank", "example ko/en",
                         "longer than 40", "ranks must be exactly"] {
            #expect(errors.contains(fragment), "missing: \(fragment)")
        }
        #expect(DeckValidator.validate(VocabDeckFile(deckId: "ko.x.1", title: "", subtitle: "", subject: .korean, entries: []))
            .contains { $0.contains("no entries") })
    }

    @Test func validatorReportsCrossFileDuplicateIDs() {
        let a = vocabFile(count: 2, deckId: "ko.test.1")
        let b = vocabFile(count: 2, deckId: "ko.test.2")
        #expect(DeckValidator.validate([a, b]).contains { $0.contains("used in both") })
    }

    @Test func idPrefixRule() {
        #expect(DeckValidator.idPrefix(for: "ko.core.1") == "ko.core")
        #expect(DeckValidator.idPrefix(for: "ko.aion2") == "ko.aion2")
        #expect(DeckValidator.isValidID("ko.core.0042", prefix: "ko.core"))
        #expect(!DeckValidator.isValidID("ko.core.42", prefix: "ko.core"))
        #expect(!DeckValidator.isValidID("ko.core.004٢", prefix: "ko.core")) // non-ASCII digit
    }

    @Test func hangulHelpers() {
        #expect(Hangul.isValidHeadword("재사용 대기시간"))
        #expect(Hangul.isValidHeadword("~에서"))
        #expect(!Hangul.isValidHeadword("ㄱ"))      // jamo, not a syllable
        #expect(!Hangul.isValidHeadword(" ~ "))     // no syllable
        #expect(!Hangul.isValidHeadword("가a"))
        #expect(Hangul.syllableCount("나는 학생이에요.") == 7)
    }
}
