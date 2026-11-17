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

    /// The result of `select`: the card, and whether picking it starts a new round (R7-F1).
    public struct Selection: Sendable, Hashable {
        public let card: Card
        /// True when the card was blocked for the current round (already shown this round, or
        /// resting after a correct answer), i.e. the round's fresh cards were used up.
        public let startsNewRound: Bool
    }

    /// Picks the next card (§10.6). See `select` for the rules.
    public func nextCard(
        history: [Card],
        stats: [ItemKey: ItemStats],
        excluded: Set<ItemKey> = [],
        blocked: Set<ItemKey> = [],
        resting: Set<ItemKey> = [],
        now: Date,
        allowFallback: Bool = true,
        rng: inout SplitMix64
    ) -> Card? {
        select(
            history: history, stats: stats, excluded: excluded, blocked: blocked, resting: resting,
            now: now, allowFallback: allowFallback, rng: &rng
        )?.card
    }

    /// Picks the next card (§10.3, §10.6).
    ///
    /// Weighted selection over the allowed set (not `excluded`; seen or in `eligibleNew`), in tiers:
    /// 1. cards not in `blocked` (fresh this round);
    /// 2. blocked cards that are not `resting` (a new round);
    /// 3. resting cards (tiny pools only).
    ///
    /// Each tier applies cooldown `K`, relaxed once to `K-1`. If every tier is empty and
    /// `allowFallback` is true, picks uniformly from the allowed set, excluding the previous card
    /// when possible. Never returns an excluded or gated card. Returns `nil` when nothing can be
    /// picked (or the fallback is disallowed).
    ///
    /// - Parameters:
    ///   - history: Cards shown this session, oldest first (including retries).
    ///   - excluded: Keys never to pick (e.g. pending retries the engine injects itself).
    ///   - blocked: Keys not to repeat in the current round (shown this round, plus `resting`).
    ///   - resting: Keys sitting out after a correct answer; the last resort before the fallback.
    ///   - allowFallback: Whether a cooldown-breaking uniform pick is allowed.
    public func select(
        history: [Card],
        stats: [ItemKey: ItemStats],
        excluded: Set<ItemKey> = [],
        blocked: Set<ItemKey> = [],
        resting: Set<ItemKey> = [],
        now: Date,
        allowFallback: Bool = true,
        rng: inout SplitMix64
    ) -> Selection? {
        guard !pool.isEmpty else { return nil }
        let calc = WeightCalculator(pool: pool, stats: stats, focus: focus, now: now, constants: constants)
        let recent = history.suffix(3)

        // Cooldown-independent weights, computed once; `tier` mirrors the eligibility predicate
        // (0 = not allowed, 1 = fresh, 2 = shown this round, 3 = resting).
        var weights = [Double](repeating: 0, count: pool.count)
        var tier = [UInt8](repeating: 0, count: pool.count)
        for (i, card) in pool.enumerated() where !excluded.contains(card.key) {
            let s = stats[card.key]
            let unseen = (s?.attempts ?? 0) == 0
            if unseen, let eligibleNew, !eligibleNew.contains(card.key) { continue }
            tier[i] = resting.contains(card.key) ? 3 : blocked.contains(card.key) ? 2 : 1
            weights[i] = calc.baseWeight(s) * deck.patternPenalty(candidate: card, recent: recent)
        }

        // Tiers in order; within each, cooldown K, relaxing once to K-1.
        let windows = Set([cooldown, max(0, cooldown - 1)]).sorted(by: >)
        let cooled = windows.map { k in Set(history.suffix(k).map(\.key)) }
        var effective = [Double](repeating: 0, count: pool.count)
        for t in UInt8(1)...3 {
            guard tier.contains(t) else { continue }
            for inCooldown in cooled {
                var total = 0.0
                for i in pool.indices {
                    let w = tier[i] == t && !inCooldown.contains(pool[i].key) ? weights[i] : 0
                    effective[i] = w
                    total += w
                }
                if total > 0 {
                    let card = pool[weightedIndex(effective, total: total, rng: &rng)]
                    return Selection(card: card, startsNewRound: t > 1)
                }
            }
        }

        guard allowFallback else { return nil }

        // Fallback: uniform over the allowed set, avoiding the previous card when possible.
        let previous = history.last?.key
        var candidates: [Card] = []
        var previousCard: Card?
        for (i, card) in pool.enumerated() where tier[i] != 0 {
            if card.key == previous { previousCard = card } else { candidates.append(card) }
        }
        guard let card = candidates.randomElement(using: &rng) ?? previousCard else { return nil }
        return Selection(card: card, startsNewRound: blocked.contains(card.key))
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
