import Foundation

/// Headline numbers of a previous session used for comparisons.
public struct SessionBaseline: Hashable, Codable, Sendable {
    public let medianMs: Double?
    public let accuracy: Double?

    public init(medianMs: Double?, accuracy: Double?) {
        self.medianMs = medianMs
        self.accuracy = accuracy
    }
}

/// Everything the Summary screen shows (§9.5).
public struct SessionSummary: Sendable, Hashable {
    public struct Row: Identifiable, Sendable, Hashable {
        public var id: UUID { attemptID }
        public let attemptID: UUID
        public let index: Int
        public let itemKey: ItemKey
        /// The card as shown, when known.
        public let card: Card?
        public let responseMs: Int
        public let correct: Bool
        public let isRetry: Bool
        /// Item EWMA before this session, for ▲/▼ comparison (`nil` if new or unknown).
        public let priorEwmaMs: Double?

        /// Ratio of this time vs. history (>1 = slower), when comparable.
        public var ratioToHistory: Double? {
            guard correct, let p = priorEwmaMs, p > 0 else { return nil }
            return Double(responseMs) / p
        }
    }

    public let sessionID: UUID
    public let deckID: DeckID
    public let config: SessionConfig
    public let startedAt: Date
    public let endedAt: Date?
    public let status: SessionStatus

    /// Counted (non-retry, non-interrupted) graded cards.
    public let gradedCount: Int
    public let correctCount: Int
    public var wrongCount: Int { gradedCount - correctCount }
    public let accuracy: Double?

    /// Timing over correct counted attempts (clamped).
    public let meanMs: Double?
    public let medianMs: Double?
    public let p90Ms: Double?
    public let fastest: Row?
    public let slowest: Row?
    public let totalDuration: TimeInterval

    public let previous: SessionBaseline?

    /// All non-interrupted attempts in order.
    public let rows: [Row]
    /// Up to 5 slowest correct counted rows, slowest first.
    public let slowest5: [Row]
    /// Counted wrong rows (one per item).
    public let wrong: [Row]

    public var baseline: SessionBaseline { SessionBaseline(medianMs: medianMs, accuracy: accuracy) }

    public var medianDeltaMs: Double? {
        guard let m = medianMs, let p = previous?.medianMs else { return nil }
        return m - p
    }

    public var medianDeltaPercent: Double? {
        guard let d = medianDeltaMs, let p = previous?.medianMs, p > 0 else { return nil }
        return d / p
    }

    public var accuracyDelta: Double? {
        guard let a = accuracy, let p = previous?.accuracy else { return nil }
        return a - p
    }

    /// Builds a summary from stored attempts (works for live sessions and history).
    public static func build(
        session: SessionRecord,
        attempts: [Attempt],
        cardLookup: (ItemKey) -> Card? = { _ in nil },
        priorEwma: [ItemKey: Double] = [:],
        previous: SessionBaseline? = nil,
        constants: SchedulerConstants = .standard
    ) -> SessionSummary {
        var rows: [Row] = []
        rows.reserveCapacity(attempts.count)
        var counted = 0
        var correct = 0
        var correctTimes: [Double] = []
        var correctRows: [Row] = []
        var wrong: [Row] = []
        var wrongKeys = Set<ItemKey>()

        for a in attempts.sorted(by: { $0.index < $1.index }) where !a.wasInterrupted {
            let row = Row(
                attemptID: a.id, index: a.index, itemKey: a.itemKey, card: cardLookup(a.itemKey),
                responseMs: a.responseMs, correct: a.correct, isRetry: a.isRetry, priorEwmaMs: priorEwma[a.itemKey]
            )
            rows.append(row)
            guard !a.isRetry else { continue }
            counted += 1
            if a.correct {
                correct += 1
                correctTimes.append(Double(constants.clamp(a.responseMs)))
                correctRows.append(row)
            } else if wrongKeys.insert(a.itemKey).inserted {
                wrong.append(row)
            }
        }

        correctTimes.sort()
        // Clamped like the rest of the summary maths; stable for equal clamped times.
        let bySpeed = correctRows.enumerated().sorted {
            let (a, b) = (constants.clamp($0.element.responseMs), constants.clamp($1.element.responseMs))
            return a != b ? a < b : $0.offset < $1.offset
        }.map(\.element)
        return SessionSummary(
            sessionID: session.id,
            deckID: session.deckID,
            config: session.config,
            startedAt: session.startedAt,
            endedAt: session.endedAt,
            status: session.status,
            gradedCount: counted,
            correctCount: correct,
            accuracy: counted > 0 ? Double(correct) / Double(counted) : nil,
            meanMs: Statistics.mean(correctTimes),
            medianMs: Statistics.percentile(sorted: correctTimes, 0.5),
            p90Ms: Statistics.percentile(sorted: correctTimes, 0.9),
            fastest: bySpeed.first,
            slowest: bySpeed.last,
            totalDuration: session.duration,
            previous: previous,
            rows: rows,
            slowest5: Array(bySpeed.suffix(5).reversed()),
            wrong: wrong
        )
    }

    /// Headline numbers only (cheap; for comparisons and trend charts).
    public static func baseline(of attempts: [Attempt], constants: SchedulerConstants = .standard) -> SessionBaseline {
        var counted = 0
        var times: [Double] = []
        for a in attempts where a.isCounted {
            counted += 1
            if a.correct { times.append(Double(constants.clamp(a.responseMs))) }
        }
        return SessionBaseline(
            medianMs: Statistics.median(times),
            accuracy: counted > 0 ? Double(times.count) / Double(counted) : nil
        )
    }
}
