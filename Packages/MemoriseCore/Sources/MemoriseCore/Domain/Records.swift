import Foundation

/// Lifecycle status of a stored session.
public enum SessionStatus: String, Codable, Sendable {
    case inProgress, completed, abandoned
}

/// A practice session as stored in history.
public struct SessionRecord: Identifiable, Codable, Sendable, Hashable {
    public let id: UUID
    public let deckID: DeckID
    public let startedAt: Date
    public var endedAt: Date?
    public var status: SessionStatus
    /// Snapshot of the configuration used.
    public let config: SessionConfig

    public init(id: UUID, deckID: DeckID, startedAt: Date, endedAt: Date? = nil, status: SessionStatus, config: SessionConfig) {
        self.id = id
        self.deckID = deckID
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.status = status
        self.config = config
    }

    /// Wall-clock duration (0 when unknown).
    public var duration: TimeInterval {
        endedAt.map { max(0, $0.timeIntervalSince(startedAt)) } ?? 0
    }

    /// Closes a session the app was killed in.
    ///
    /// With ≥ 1 counted attempt: `.completed`, ended at the latest `shownAt + responseMs + gradeMs`.
    /// Otherwise: `.abandoned`, ended at the last attempt's `shownAt` (or `startedAt`).
    public func closedAfterInterruption(attempts: [Attempt]) -> SessionRecord {
        var r = self
        if attempts.contains(where: \.isCounted) {
            r.status = .completed
            r.endedAt = attempts.map { $0.shownAt.addingTimeInterval(Double($0.responseMs + $0.gradeMs) / 1_000) }.max()
        } else {
            r.status = .abandoned
            r.endedAt = attempts.map(\.shownAt).max() ?? startedAt
        }
        return r
    }
}

/// One answer to one card.
public struct Attempt: Identifiable, Codable, Sendable, Hashable {
    public let id: UUID
    public let sessionID: UUID
    public let itemKey: ItemKey
    public let deckID: DeckID
    /// Position in session (0-based, across all stored attempts).
    public let index: Int
    /// Wall clock, history only.
    public let shownAt: Date
    /// Prompt fully shown → OK tapped (monotonic clock). Raw, unclamped.
    public let responseMs: Int
    /// OK tapped → grade tapped.
    public let gradeMs: Int
    public let correct: Bool
    /// Re-shown after a wrong answer in the same session.
    public let isRetry: Bool
    /// App left the foreground / paused while the prompt was visible.
    public let wasInterrupted: Bool

    public init(
        id: UUID, sessionID: UUID, itemKey: ItemKey, deckID: DeckID, index: Int, shownAt: Date,
        responseMs: Int, gradeMs: Int, correct: Bool, isRetry: Bool, wasInterrupted: Bool
    ) {
        self.id = id
        self.sessionID = sessionID
        self.itemKey = itemKey
        self.deckID = deckID
        self.index = index
        self.shownAt = shownAt
        self.responseMs = responseMs
        self.gradeMs = gradeMs
        self.correct = correct
        self.isRetry = isRetry
        self.wasInterrupted = wasInterrupted
    }

    /// Whether this attempt feeds item statistics and summary maths.
    @inlinable public var isCounted: Bool { !isRetry && !wasInterrupted }
}

/// Aggregated learning statistics for one item.
public struct ItemStats: Codable, Sendable, Equatable, Hashable {
    public let itemKey: ItemKey
    public let deckID: DeckID
    /// Counted attempts (excludes retries & interrupted).
    public var attempts: Int
    public var correctCount: Int
    /// EWMA over correct counted attempts only.
    public var ewmaResponseMs: Double?
    /// 0…1, EWMA of (wrong ? 1 : 0).
    public var ewmaError: Double
    public var bestResponseMs: Int?
    public var lastSeenAt: Date?
    public var lastWrongAt: Date?

    public init(
        itemKey: ItemKey, deckID: DeckID, attempts: Int = 0, correctCount: Int = 0,
        ewmaResponseMs: Double? = nil, ewmaError: Double = 0, bestResponseMs: Int? = nil,
        lastSeenAt: Date? = nil, lastWrongAt: Date? = nil
    ) {
        self.itemKey = itemKey
        self.deckID = deckID
        self.attempts = attempts
        self.correctCount = correctCount
        self.ewmaResponseMs = ewmaResponseMs
        self.ewmaError = ewmaError
        self.bestResponseMs = bestResponseMs
        self.lastSeenAt = lastSeenAt
        self.lastWrongAt = lastWrongAt
    }

    /// Fresh, never-attempted stats.
    public static func empty(key: ItemKey, deck: DeckID) -> ItemStats {
        ItemStats(itemKey: key, deckID: deck)
    }

    /// Lifetime accuracy, `nil` when never attempted.
    public var accuracy: Double? {
        attempts > 0 ? Double(correctCount) / Double(attempts) : nil
    }
}
