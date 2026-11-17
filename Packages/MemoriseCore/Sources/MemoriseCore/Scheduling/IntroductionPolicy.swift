/// Decides which unseen cards may be introduced in a session (§10.5).
public enum IntroductionPolicy {
    /// Keys of unseen cards eligible this session, or `nil` when the deck has no gating.
    ///
    /// The next `newPerSession` unseen *ranks* (entries) are eligible — both directions of an
    /// entry share a rank. If the distinct entries available (seen + eligible) would be fewer than
    /// `max(minEligiblePool, targetDistinct)` (capped at the pool's entry count), further ranks
    /// are added in order until there are enough (fill rule). Counting entries, not cards, keeps a
    /// two-direction session from being filled by the same words twice (R7-F1).
    ///
    /// - Parameter targetDistinct: Distinct entries the session will show (its card count, or an
    ///   estimate for minute-based sessions). `0` keeps the plain `minEligiblePool` floor.
    public static func eligibleNewKeys(
        pool: [Card],
        stats: [ItemKey: ItemStats],
        deck: any Deck,
        newPerSession: Int,
        targetDistinct: Int = 0,
        constants: SchedulerConstants = .standard
    ) -> Set<ItemKey>? {
        var seenRanks = Set<Int>()
        var unrankedSeen = 0
        var unseenByRank: [Int: [ItemKey]] = [:]
        var gated = false
        for card in pool {
            let rank = deck.introductionRank(of: card)
            if let s = stats[card.key], s.attempts > 0 {
                if let rank { seenRanks.insert(rank) } else { unrankedSeen += 1 }
                continue
            }
            guard let rank else { continue }
            gated = true
            unseenByRank[rank, default: []].append(card.key)
        }
        guard gated else { return nil }

        let totalUnits = seenRanks.union(unseenByRank.keys).count + unrankedSeen
        let minUnits = min(totalUnits, max(constants.minEligiblePool, targetDistinct))
        var units = seenRanks.count + unrankedSeen
        var eligible = Set<ItemKey>()
        for (i, rank) in unseenByRank.keys.sorted().enumerated() {
            guard i < max(newPerSession, 0) || units < minUnits else { break }
            eligible.formUnion(unseenByRank[rank]!)
            if !seenRanks.contains(rank) { units += 1 }
        }
        return eligible
    }
}
