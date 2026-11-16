import Foundation

/// Applies one counted attempt to an item's statistics (§9.4).
public enum StatsUpdater {
    public static func apply(
        responseMs: Int,
        correct: Bool,
        at now: Date,
        to stats: ItemStats,
        constants: SchedulerConstants = .standard
    ) -> ItemStats {
        var s = stats
        let t = constants.clamp(responseMs)
        s.attempts += 1
        if correct {
            s.correctCount += 1
            let td = Double(t)
            s.ewmaResponseMs = s.ewmaResponseMs.map { constants.alphaTime * td + (1 - constants.alphaTime) * $0 } ?? td
            s.bestResponseMs = min(s.bestResponseMs ?? t, t)
            s.ewmaError = (1 - constants.alphaError) * s.ewmaError
        } else {
            // A wrong answer's time never updates the time EWMA.
            s.ewmaError = constants.alphaError + (1 - constants.alphaError) * s.ewmaError
            s.lastWrongAt = now
        }
        s.lastSeenAt = now
        return s
    }

    /// Convenience for an `Attempt`. Returns `stats` unchanged for non-counted attempts.
    public static func apply(_ attempt: Attempt, at now: Date, to stats: ItemStats, constants: SchedulerConstants = .standard) -> ItemStats {
        guard attempt.isCounted else { return stats }
        return apply(responseMs: attempt.responseMs, correct: attempt.correct, at: now, to: stats, constants: constants)
    }
}
