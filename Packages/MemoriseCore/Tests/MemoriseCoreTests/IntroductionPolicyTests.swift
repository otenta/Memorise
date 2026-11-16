import Testing
@testable import MemoriseCore

/// PLAN §10.5 introduction gating (+ §17 decision: fill rule ≥ 6, ranks count entries).
@Suite("Introduction gating (§10.5)")
struct IntroductionPolicyTests {
    @Test func fretboardHasNoGating() {
        let deck = FretboardNotesDeck()
        #expect(IntroductionPolicy.eligibleNewKeys(pool: fretboardCards(), stats: [:], deck: deck, newPerSession: 1) == nil)
    }

    @Test func onlyTheNextNewPerSessionRanksAreEligible() {
        let deck = vocabDeck(count: 200)
        let pool = deck.cards(options: .vocab(VocabOptions()))
        let eligible = IntroductionPolicy.eligibleNewKeys(pool: pool, stats: [:], deck: deck, newPerSession: 10)!
        #expect(eligible == Set((1...10).map { VocabDeck.itemKey(entryID: entryID($0), direction: .koToEn) }))
    }

    @Test func bothDirectionsShareARank() {
        let deck = vocabDeck(count: 50)
        let pool = deck.cards(options: .vocab(VocabOptions(direction: .both)))
        let eligible = IntroductionPolicy.eligibleNewKeys(pool: pool, stats: [:], deck: deck, newPerSession: 10)!
        #expect(eligible.count == 20)
    }

    @Test func seenCardsAreSkippedAndNextRanksIntroduced() {
        let deck = vocabDeck(count: 50)
        let pool = deck.cards(options: .vocab(VocabOptions()))
        let stats = Dictionary(uniqueKeysWithValues: pool.prefix(10).map { ($0.key, seenStats($0.key, deck: deck.id)) })
        let eligible = IntroductionPolicy.eligibleNewKeys(pool: pool, stats: stats, deck: deck, newPerSession: 3)!
        #expect(eligible == Set(pool[10..<13].map(\.key)))
    }

    @Test func fillRuleTopsUpToMinimumPool() {
        let deck = vocabDeck(count: 50)
        let pool = deck.cards(options: .vocab(VocabOptions()))
        // Nothing seen, newPerSession 0 → fill to 6.
        #expect(IntroductionPolicy.eligibleNewKeys(pool: pool, stats: [:], deck: deck, newPerSession: 0)!.count == 6)
        #expect(IntroductionPolicy.eligibleNewKeys(pool: pool, stats: [:], deck: deck, newPerSession: -5)!.count == 6)
        // 3 seen + newPerSession 1 → 3 more unseen.
        let stats = Dictionary(uniqueKeysWithValues: pool.prefix(3).map { ($0.key, seenStats($0.key, deck: deck.id)) })
        #expect(IntroductionPolicy.eligibleNewKeys(pool: pool, stats: stats, deck: deck, newPerSession: 1)!.count == 3)
        // Small pool: min(6, pool) caps the fill.
        let small = vocabDeck(count: 4)
        let smallPool = small.cards(options: .vocab(VocabOptions()))
        #expect(IntroductionPolicy.eligibleNewKeys(pool: smallPool, stats: [:], deck: small, newPerSession: 0)!.count == 4)
    }

    @Test func zeroAttemptStatsCountAsUnseen() {
        let deck = vocabDeck(count: 20)
        let pool = deck.cards(options: .vocab(VocabOptions()))
        let stats = [pool[0].key: ItemStats.empty(key: pool[0].key, deck: deck.id)]
        let eligible = IntroductionPolicy.eligibleNewKeys(pool: pool, stats: stats, deck: deck, newPerSession: 6)!
        #expect(eligible.contains(pool[0].key))
    }

    /// §10.7: 200 unseen, newPerSession 10, a 20-card session introduces exactly the 10 lowest-rank entries.
    @Test func twentyCardSessionIntroducesExactlyTenLowestRanks() {
        let deck = vocabDeck(count: 200)
        let config = SessionConfig(deckID: deck.id, options: .vocab(VocabOptions(newPerSession: 10)), length: .cards(20))
        let (engine, clock) = makeEngine(deck: deck, config: config, seed: 5)
        _ = engine.start()
        driveUntilFinished(engine, clock: clock) { _ in true }
        let ranks = Set(engine.attempts.compactMap { a in deck.entries.first { VocabDeck.itemKey(entryID: $0.id, direction: .koToEn) == a.itemKey }?.rank })
        #expect(ranks == Set(1...10))
        #expect(engine.countedGraded == 20)
    }
}
