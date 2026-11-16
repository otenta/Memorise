/// Decides which unseen cards may be introduced in a session (§10.5).
public enum IntroductionPolicy {
    /// Keys of unseen cards eligible this session, or `nil` when the deck has no gating.
    ///
    /// The next `newPerSession` unseen *ranks* (entries) are eligible — both directions of an
    /// entry share a rank. If seen + eligible cards would be fewer than `minEligiblePool`,
    /// further ranks are added in order until the pool is large enough (fill rule).
    public static func eligibleNewKeys(
        pool: [Card],
        stats: [ItemKey: ItemStats],
        deck: any Deck,
        newPerSession: Int,
        constants: SchedulerConstants = .standard
    ) -> Set<ItemKey>? {
        var seenCount = 0
        var unseenByRank: [Int: [ItemKey]] = [:]
        var gated = false
        for card in pool {
            if let s = stats[card.key], s.attempts > 0 {
                seenCount += 1
                continue
            }
            guard let rank = deck.introductionRank(of: card) else { continue }
            gated = true
            unseenByRank[rank, default: []].append(card.key)
        }
        guard gated else { return nil }

        let minPool = min(constants.minEligiblePool, pool.count)
        var eligible = Set<ItemKey>()
        for (i, rank) in unseenByRank.keys.sorted().enumerated() {
            guard i < max(newPerSession, 0) || seenCount + eligible.count < minPool else { break }
            eligible.formUnion(unseenByRank[rank]!)
        }
        return eligible
    }
}
