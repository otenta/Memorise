import Testing
@testable import MemoriseCore

/// PLAN §8.1, §10.4 (vocab), F9 P3-2.
@Suite("Vocab deck (§8.1)")
struct VocabDeckTests {
    @Test func itemKeyFormatAndRawValuesAreStable() {
        #expect(VocabDeck.itemKey(entryID: "ko.core.0042", direction: .koToEn).raw == "ko.core.0042#ko-en")
        #expect(VocabDeck.itemKey(entryID: "ko.core.0042", direction: .enToKo).raw == "ko.core.0042#en-ko")
        #expect(VocabDirection.koToEn.rawValue == "ko-en")
        #expect(VocabDirection.enToKo.rawValue == "en-ko")
    }

    @Test func directionsProduceSeparateItems() {
        let deck = vocabDeck(count: 5)
        #expect(deck.cards(options: .vocab(VocabOptions(direction: .koToEn))).count == 5)
        #expect(deck.cards(options: .vocab(VocabOptions(direction: .enToKo))).allSatisfy { $0.vocab?.direction == .enToKo })
        let both = deck.cards(options: .vocab(VocabOptions(direction: .both)))
        #expect(both.count == 10)
        #expect(Set(both.map(\.key)).count == 10)
        #expect(deck.cards(options: .fretboard(FretboardOptions())).isEmpty)
    }

    @Test func defaultsMatchSpec() {
        let o = VocabOptions()
        #expect(o.direction == .koToEn)
        #expect(o.newPerSession == 10)
        #expect(o.autoPlayAudio)
        #expect(o.tags.isEmpty)
    }

    @Test func tagFilter() {
        let deck = vocabDeck(count: 6) { $0 <= 2 ? ["combat"] : ($0 <= 4 ? ["ui", "combat"] : ["ui"]) }
        #expect(deck.allTags == ["combat", "ui"])
        #expect(deck.cards(options: .vocab(VocabOptions(tags: ["combat"]))).count == 4)
        #expect(deck.cards(options: .vocab(VocabOptions(tags: ["ui"]))).count == 4)
        #expect(deck.cards(options: .vocab(VocabOptions(tags: ["nope"]))).isEmpty)
        #expect(deck.cards(options: .vocab(VocabOptions())).count == 6)
    }

    @Test func sanitizedDropsStaleTags() {
        let o = VocabOptions(tags: ["combat", "removed"]).sanitized(allTags: ["combat", "ui"])
        #expect(o.tags == ["combat"])
    }

    @Test func entriesSortedByRankAndRankUsedForIntroduction() {
        let file = VocabDeckFile(deckId: "ko.test.1", title: "T", subtitle: "", subject: .korean,
                                 entries: [vocabEntry(3), vocabEntry(1), vocabEntry(2)])
        let deck = VocabDeck(file: file)
        #expect(deck.entries.map(\.rank) == [1, 2, 3])
        let cards = deck.cards(options: .vocab(VocabOptions(direction: .both)))
        #expect(cards.map { deck.introductionRank(of: $0)! } == [1, 1, 2, 2, 3, 3])
    }

    @Test func patternPenaltyRules() {
        let deck = vocabDeck(count: 4) { $0 == 4 ? [] : ["combat"] }
        let both = deck.cards(options: .vocab(VocabOptions(direction: .both)))
        func c(_ n: Int, _ d: VocabDirection) -> Card { both.first { $0.vocab!.entry.rank == n && $0.vocab!.direction == d }! }

        #expect(deck.patternPenalty(candidate: c(1, .koToEn), recent: []) == 1)
        // Same entry, other direction, immediately before → ×0.1.
        #expect(abs(deck.patternPenalty(candidate: c(1, .enToKo), recent: [c(1, .koToEn)][...]) - 0.1) < 1e-12)
        // Tag shared with both of the previous two → ×0.7.
        #expect(deck.patternPenalty(candidate: c(3, .koToEn), recent: [c(1, .koToEn), c(2, .koToEn)][...]) == 0.7)
        // Shared with only one of them → no penalty.
        #expect(deck.patternPenalty(candidate: c(3, .koToEn), recent: [c(4, .koToEn), c(2, .koToEn)][...]) == 1)
        // Untagged candidate → no tag penalty.
        #expect(deck.patternPenalty(candidate: c(4, .koToEn), recent: [c(1, .koToEn), c(2, .koToEn)][...]) == 1)
    }
}
