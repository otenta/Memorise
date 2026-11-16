import Foundation
import Testing
@testable import MemoriseCore

/// PLAN §10.3–§10.7 required scheduler tests, F3 (P2-1).
@Suite("Scheduler (§10)")
struct SchedulerTests {
    let deck = FretboardNotesDeck()

    private func scheduler(_ pool: [Card]? = nil, focus: FocusLevel = .normal, eligibleNew: Set<ItemKey>? = nil, deck: (any Deck)? = nil) -> Scheduler {
        Scheduler(deck: deck ?? self.deck, pool: pool ?? fretboardCards(), focus: focus, eligibleNew: eligibleNew)
    }

    /// Draws `sessions × length` cards, each session starting from an empty history.
    private func simulate(_ s: Scheduler, stats: [ItemKey: ItemStats] = [:], sessions: Int, length: Int, seed: UInt64,
                          window: Int? = nil, onPick: (Card, [Card]) -> Void) {
        var rng = SplitMix64(seed: seed)
        for _ in 0..<sessions {
            var history: [Card] = []
            for _ in 0..<length {
                let h = window.map { Array(history.suffix($0)) } ?? history
                guard let c = s.nextCard(history: h, stats: stats, now: fixedNow, rng: &rng) else {
                    Issue.record("scheduler returned nil"); return
                }
                onPick(c, history)
                history.append(c)
            }
        }
    }

    @Test func sameSeedSameSequence() {
        let s = scheduler()
        func run(_ seed: UInt64) -> [ItemKey] {
            var out: [ItemKey] = []
            simulate(s, sessions: 1, length: 200, seed: seed) { c, _ in out.append(c.key) }
            return out
        }
        #expect(run(7) == run(7))
        #expect(run(7) != run(8))
    }

    @Test func noRepeatWithinCooldownOver10000Draws() {
        let s = scheduler()
        #expect(s.cooldown == 3)
        var draws = 0
        simulate(s, sessions: 200, length: 50, seed: 1) { c, history in
            draws += 1
            #expect(!history.suffix(3).contains(c), "repeat within K")
        }
        #expect(draws == 10_000)
    }

    @Test func sameStringBackToBackBelowUniformRate() {
        var same = 0, draws = 0
        simulate(scheduler(), sessions: 200, length: 50, seed: 2) { c, history in
            guard let prev = history.last else { return }
            draws += 1
            if prev.fretboardNote!.stringNumber == c.fretboardNote!.stringNumber { same += 1 }
        }
        let rate = Double(same) / Double(draws)
        // Uniform would be ≈ 1/6 (16.7 %); the ×0.35 penalty should push it well below.
        #expect(rate < 0.10, "same-string rate \(rate)")
    }

    @Test func slowCardDrawnAtLeastTwiceAsOftenAsMedianCard() {
        let pool = fretboardCards()
        var stats = Dictionary(uniqueKeysWithValues: pool.map { ($0.key, seenStats($0.key, ewma: 2_000)) })
        let slow = pool[10].key, median = pool[20].key
        stats[slow] = seenStats(slow, ewma: 6_000)
        var counts: [ItemKey: Int] = [:]
        simulate(scheduler(pool), stats: stats, sessions: 1, length: 10_000, seed: 3, window: 3) { c, _ in counts[c.key, default: 0] += 1 }
        #expect(Double(counts[slow] ?? 0) >= 2 * Double(counts[median] ?? 1), "slow \(counts[slow] ?? 0) vs median \(counts[median] ?? 0)")
    }

    @Test func wrongHeavyCardDrawnMoreOften() {
        let pool = fretboardCards()
        var stats = Dictionary(uniqueKeysWithValues: pool.map { ($0.key, seenStats($0.key, ewma: 2_000)) })
        let wrong = pool[5].key, right = pool[30].key
        stats[wrong] = seenStats(wrong, ewma: 2_000, error: 0.8)
        var counts: [ItemKey: Int] = [:]
        simulate(scheduler(pool), stats: stats, sessions: 1, length: 10_000, seed: 4, window: 3) { c, _ in counts[c.key, default: 0] += 1 }
        #expect((counts[wrong] ?? 0) > 2 * (counts[right] ?? 0))
    }

    @Test func offFocusIsApproximatelyUniform() {
        let pool = fretboardCards()
        // Strongly skewed stats must be ignored at .off.
        let stats = Dictionary(uniqueKeysWithValues: pool.enumerated().map { ($1.key, seenStats($1.key, ewma: Double(500 + $0 * 500), error: Double($0) / 42)) })
        let s = Scheduler(deck: UniformDeck(), pool: pool, focus: .off, eligibleNew: nil)
        var counts: [ItemKey: Int] = [:]
        let n = 21_000
        simulate(s, stats: stats, sessions: 1, length: n, seed: 5, window: 3) { c, _ in counts[c.key, default: 0] += 1 }
        let expected = Double(n) / Double(pool.count)
        let chi2 = pool.reduce(0.0) { acc, c in
            let o = Double(counts[c.key] ?? 0)
            return acc + (o - expected) * (o - expected) / expected
        }
        #expect(chi2 < 74.7, "chi² = \(chi2) (41 df, p = 0.001)")
    }

    @Test func alreadyShownCardsAreDampedButNotForbidden() {
        // 5-card pool, long session: every card keeps appearing.
        let pool = Array(fretboardCards().prefix(5))
        var counts: [ItemKey: Int] = [:]
        simulate(scheduler(pool), sessions: 1, length: 500, seed: 6) { c, _ in counts[c.key, default: 0] += 1 }
        #expect(counts.count == 5)
    }

    @Test func excludedCardsAreNeverPicked() {
        let pool = fretboardCards()
        let excluded = Set(pool.prefix(40).map(\.key))
        var rng = SplitMix64(seed: 1)
        for _ in 0..<500 {
            let c = scheduler(pool).nextCard(history: [], stats: [:], excluded: excluded, now: fixedNow, rng: &rng)
            #expect(c.map { !excluded.contains($0.key) } == true)
        }
        #expect(scheduler(pool).nextCard(history: [], stats: [:], excluded: Set(pool.map(\.key)), now: fixedNow, rng: &rng) == nil)
        #expect(scheduler([]).nextCard(history: [], stats: [:], now: fixedNow, rng: &rng) == nil)
    }

    @Test func cooldownRelaxesOnceForTinyPools() {
        // Pool 2 → K = 1: alternates strictly.
        let pool = Array(fretboardCards().prefix(2))
        var prev: Card?
        simulate(scheduler(pool), sessions: 1, length: 100, seed: 9) { c, h in
            if let p = h.last { #expect(c != p) }
            prev = c
        }
        _ = prev
        // Pool 1 → K = 0: the single card repeats.
        let one = Array(fretboardCards().prefix(1))
        var rng = SplitMix64(seed: 1)
        #expect(scheduler(one).nextCard(history: one, stats: [:], now: fixedNow, rng: &rng) == one[0])
    }

    // MARK: F3 — fallback respects exclusions and gating

    @Test func fallbackDisallowedReturnsNilWhenCooldownBlocksEverything() {
        let pool = Array(fretboardCards().prefix(4))
        let (a, b, c, d) = (pool[0], pool[1], pool[2], pool[3])
        let s = scheduler(pool)
        var rng = SplitMix64(seed: 1)
        // K = 3 relaxed to 2 still blocks a, b; c and d are pending retries.
        #expect(s.nextCard(history: [a, b], stats: [:], excluded: [c.key, d.key], now: fixedNow, allowFallback: false, rng: &rng) == nil)
        for _ in 0..<50 {
            let pick = s.nextCard(history: [a, b], stats: [:], excluded: [c.key, d.key], now: fixedNow, rng: &rng)
            #expect(pick == a, "fallback must avoid excluded cards and the previous card")
        }
    }

    @Test func fallbackNeverReturnsGatedUnseenCard() {
        let deck = vocabDeck(count: 30)
        let pool = deck.cards(options: .vocab(VocabOptions()))
        let eligible = Set(pool.prefix(2).map(\.key))
        let s = Scheduler(deck: deck, pool: pool, focus: .normal, eligibleNew: eligible)
        var rng = SplitMix64(seed: 11)
        for seed in 0..<200 as Range<UInt64> {
            rng = SplitMix64(seed: seed)
            let pick = s.nextCard(history: [pool[0], pool[1]], stats: [:], now: fixedNow, rng: &rng)
            #expect(pick.map { eligible.contains($0.key) } == true, "picked gated card \(pick?.key.raw ?? "nil")")
        }
    }

    @Test func gatedUnseenCardsNeverPickedInNormalSelection() {
        let deck = vocabDeck(count: 30)
        let pool = deck.cards(options: .vocab(VocabOptions()))
        let eligible = Set(pool.prefix(10).map(\.key))
        let s = Scheduler(deck: deck, pool: pool, focus: .normal, eligibleNew: eligible)
        simulate(s, sessions: 20, length: 20, seed: 12) { c, _ in #expect(eligible.contains(c.key)) }
    }
}

/// Deck without pattern penalties, to isolate the uniform-focus check.
private struct UniformDeck: Deck {
    let id: DeckID = FretboardNotesDeck.deckID
    let title = "Uniform", subtitle = ""
    let subject = Subject.music
    var defaultOptions: DeckOptions { .fretboard(FretboardOptions()) }
    func cards(options: DeckOptions) -> [Card] { FretboardNotesDeck().cards(options: options) }
    func patternPenalty(candidate: Card, recent: ArraySlice<Card>) -> Double { 1 }
}
