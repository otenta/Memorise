import Foundation

/// Deck coverage (R8-S2): the share of the pool's cards whose last counted answer was correct.
public enum DeckCoverage {
    /// Pool cards attempted whose last counted answer was correct. Stats outside the pool are ignored.
    public static func coveredCount(poolKeys: [ItemKey], stats: [ItemKey: ItemStats]) -> Int {
        var n = 0
        for key in poolKeys {
            if let s = stats[key], s.attempts > 0, !s.lastAnswerWasWrong { n += 1 }
        }
        return n
    }

    /// `coveredCount / poolKeys.count`; `nil` while no pool card has been attempted (deck is "New").
    public static func fraction(poolKeys: [ItemKey], stats: [ItemKey: ItemStats]) -> Double? {
        guard !poolKeys.isEmpty, poolKeys.contains(where: { (stats[$0]?.attempts ?? 0) > 0 }) else { return nil }
        return Double(coveredCount(poolKeys: poolKeys, stats: stats)) / Double(poolKeys.count)
    }
}
