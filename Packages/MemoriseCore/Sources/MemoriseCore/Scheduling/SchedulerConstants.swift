/// Every tunable scheduling / stats constant (§9.4, §10). Update PLAN.md if changed.
public struct SchedulerConstants: Sendable, Hashable {
    public var alphaTime = 0.3
    public var alphaError = 0.3
    public var minResponseMs = 150
    public var maxResponseMs = 30_000
    /// Reference time when no card in the pool has a time EWMA.
    public var fallbackReferenceMs = 4_000.0
    public var minRatio = 0.33
    public var maxRatio = 4.0
    /// Weight of an unseen card.
    public var newCardWeight = 1.5
    public var weightFloor = 0.05
    public var staleDays = 14.0
    /// Unused since R7-F1 (in-session repeats are governed by rounds; see `correctRestRounds`).
    /// Kept so defaults and any stored constant sets stay unchanged.
    public var alreadyShownFactor = 0.2
    /// Extra rounds a card answered correctly sits out before it may be picked again (R7-F1).
    public var correctRestRounds = 1
    /// Cards shown per minute, used to size minute-based sessions for introduction gating (R7-F1).
    public var cardsPerMinuteEstimate = 8
    /// Max cooldown window (`K = min(maxCooldown, pool.count - 1)`).
    public var maxCooldown = 3
    /// Retry re-appears after this many further cards.
    public var retryDelay = 3...5
    /// A missed card waits a random number of this deck's completed sessions in this range before
    /// it may return (R8-S1; the gap is stable per miss).
    public var wrongGapSessions = 2...4
    /// Max fraction of a session's entries that are returning wrong cards while new material remains (R8-S1).
    public var reviewShare = 0.3
    /// Ceiling of the review share. The share grows from `reviewShare` to this as the due backlog reaches the
    /// session's entry target: `reviewShare + (reviewShareMax - reviewShare) × min(1, due ÷ target)` (R7-4).
    public var reviewShareMax = 0.6
    /// A killed session with fewer counted attempts than this is closed as abandoned, so it doesn't advance
    /// "sessions since a miss" or become the baseline (R7-3).
    public var minCountedForKilledSession = 5
    /// Minimum eligible pool size before introduction gating is relaxed.
    public var minEligiblePool = 6
    /// Grades arriving sooner than this after the reveal are ignored (guards against double-taps).
    public var gradeLockoutMs = 250

    public init() {}

    public static let standard = SchedulerConstants()

    @inlinable public func clamp(_ ms: Int) -> Int { min(max(ms, minResponseMs), maxResponseMs) }
}
