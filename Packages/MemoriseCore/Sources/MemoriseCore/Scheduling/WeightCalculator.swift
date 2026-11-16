import Foundation

/// Computes the stats-based base weight of a card (§10.2).
public struct WeightCalculator: Sendable {
    public let focus: FocusLevel
    public let now: Date
    public let constants: SchedulerConstants
    /// Median time EWMA over the pool (fallback when none).
    public let referenceMs: Double

    public init(
        pool: [Card],
        stats: [ItemKey: ItemStats],
        focus: FocusLevel,
        now: Date,
        constants: SchedulerConstants = .standard
    ) {
        self.focus = focus
        self.now = now
        self.constants = constants
        let times = pool.compactMap { stats[$0.key]?.ewmaResponseMs }
        self.referenceMs = Statistics.median(times) ?? constants.fallbackReferenceMs
    }

    /// Base weight before in-session adjustments. `nil` stats (or 0 attempts) = unseen.
    public func baseWeight(_ stats: ItemStats?) -> Double {
        guard focus != .off else { return 1 }
        guard let s = stats, s.attempts > 0 else { return constants.newCardWeight }
        let ratio = min(max((s.ewmaResponseMs ?? referenceMs) / referenceMs, constants.minRatio), constants.maxRatio)
        let slow = pow(ratio, focus.gamma)
        let err = 1 + focus.errorWeight * s.ewmaError
        let unc = 1 + 1 / Double(s.attempts)
        let days = s.lastSeenAt.map { max(0, now.timeIntervalSince($0)) / 86_400 } ?? constants.staleDays
        let stale = 1 + min(days, constants.staleDays) / constants.staleDays
        return max(slow * err * unc * stale, constants.weightFloor)
    }
}
