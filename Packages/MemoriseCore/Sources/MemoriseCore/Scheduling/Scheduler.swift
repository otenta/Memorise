import Foundation

/// Adaptive weighted-random card selection with anti-pattern rules (§10).
///
/// Deterministic for a given RNG state. Built once per session; `nextCard` is O(pool).
public struct Scheduler: Sendable {
    public let deck: any Deck
    public let pool: [Card]
    public let focus: FocusLevel
    public let constants: SchedulerConstants
    /// Unseen cards allowed this session (`nil` = no gating).
    public let eligibleNew: Set<ItemKey>?

    public init(
        deck: any Deck,
        pool: [Card],
        focus: FocusLevel,
        eligibleNew: Set<ItemKey>?,
        constants: SchedulerConstants = .standard
    ) {
        self.deck = deck
        self.pool = pool
        self.focus = focus
        self.eligibleNew = eligibleNew
        self.constants = constants
    }

    /// Cooldown window `K`.
    public var cooldown: Int { max(0, min(constants.maxCooldown, pool.count - 1)) }

    /// Picks the next card (§10.6).
    ///
    /// Weighted selection with cooldown `K`, relaxed once to `K-1`. If nothing is eligible and
    /// `allowFallback` is true, picks uniformly from the *allowed set* (not `excluded`, and seen or
    /// in `eligibleNew`), excluding the previous card when possible. Never returns an excluded or
    /// gated card. Returns `nil` when nothing can be picked (or the fallback is disallowed).
    ///
    /// - Parameters:
    ///   - history: Cards shown this session, oldest first (including retries).
    ///   - excluded: Keys never to pick (e.g. pending retries the engine injects itself).
    ///   - allowFallback: Whether a cooldown-breaking uniform pick is allowed.
    public func nextCard(
        history: [Card],
        stats: [ItemKey: ItemStats],
        excluded: Set<ItemKey> = [],
        now: Date,
        allowFallback: Bool = true,
        rng: inout SplitMix64
    ) -> Card? {
        guard !pool.isEmpty else { return nil }
        let calc = WeightCalculator(pool: pool, stats: stats, focus: focus, now: now, constants: constants)
        let recent = history.suffix(3)
        var shown = Set<ItemKey>(minimumCapacity: history.count)
        for c in history { shown.insert(c.key) }

        // Cooldown-independent weights, computed once; `allowed` mirrors the eligibility predicate.
        var weights = [Double](repeating: 0, count: pool.count)
        var allowed = [Bool](repeating: false, count: pool.count)
        for (i, card) in pool.enumerated() where !excluded.contains(card.key) {
            let s = stats[card.key]
            let unseen = (s?.attempts ?? 0) == 0
            if unseen, let eligibleNew, !eligibleNew.contains(card.key) { continue }
            allowed[i] = true
            var w = calc.baseWeight(s)
            if shown.contains(card.key) { w *= constants.alreadyShownFactor }
            w *= deck.patternPenalty(candidate: card, recent: recent)
            weights[i] = w
        }

        // Apply cooldown K, relaxing to K-1 if nothing is eligible.
        var k = cooldown
        while true {
            let blocked = Set(history.suffix(k).map(\.key))
            var total = 0.0
            var effective = weights
            for i in effective.indices {
                if blocked.contains(pool[i].key) { effective[i] = 0 }
                total += effective[i]
            }
            if total > 0 { return pool[weightedIndex(effective, total: total, rng: &rng)] }
            if k == 0 || k < cooldown { break }
            k -= 1
        }

        guard allowFallback else { return nil }

        // Fallback: uniform over the allowed set, avoiding the previous card when possible.
        let previous = history.last?.key
        var candidates: [Card] = []
        var previousCard: Card?
        for (i, card) in pool.enumerated() where allowed[i] {
            if card.key == previous { previousCard = card } else { candidates.append(card) }
        }
        if candidates.isEmpty, let previousCard { return previousCard }
        return candidates.randomElement(using: &rng)
    }

    @inline(__always)
    private func weightedIndex(_ weights: [Double], total: Double, rng: inout SplitMix64) -> Int {
        var r = Double.random(in: 0..<total, using: &rng)
        var last = 0
        for (i, w) in weights.enumerated() where w > 0 {
            if r < w { return i }
            r -= w
            last = i
        }
        return last // floating-point guard
    }
}
