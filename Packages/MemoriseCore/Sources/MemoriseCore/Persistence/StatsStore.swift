import Foundation

/// Persistence boundary. The app implements it with SwiftData; core ships an in-memory actor.
public protocol StatsStore: Sendable {
    func stats(for deck: DeckID) async throws -> [ItemKey: ItemStats]
    func save(_ stats: ItemStats) async throws
    func save(_ attempt: Attempt) async throws
    func upsert(_ session: SessionRecord) async throws
    /// Sessions of a deck, oldest first.
    func sessions(for deck: DeckID) async throws -> [SessionRecord]
    /// Attempts of a session, ordered by index.
    func attempts(for session: UUID) async throws -> [Attempt]
    /// All attempts of a deck, ordered by `shownAt`, then `index`.
    func attempts(forDeck deck: DeckID) async throws -> [Attempt]
    /// Headline numbers of every completed session of a deck, ordered by `startedAt`.
    /// Has a default implementation (runs off the caller's actor).
    func trendPoints(for deck: DeckID) async throws -> [SessionTrendPoint]
    /// Closes every `.inProgress` session left by a killed app (call at launch, before other access).
    /// See `SessionRecord.closedAfterInterruption(attempts:)` for the rule.
    func closeInterruptedSessions() async throws
    func reset(deck: DeckID) async throws
    func resetAll() async throws
    func exportSnapshot() async throws -> ExportSnapshot
}

public extension StatsStore {
    /// Applies a single engine effect.
    func apply(_ effect: SessionEffect) async throws {
        switch effect {
        case let .upsertSession(s): try await upsert(s)
        case let .saveAttempt(a): try await save(a)
        case let .saveStats(s): try await save(s)
        }
    }

    func trendPoints(for deck: DeckID) async throws -> [SessionTrendPoint] {
        async let sessions = sessions(for: deck)
        async let attempts = attempts(forDeck: deck)
        let bySession = Dictionary(grouping: try await attempts, by: \.sessionID)
        return try await sessions
            .filter { $0.status == .completed }
            .sorted { $0.startedAt < $1.startedAt }
            .map { s in
                let a = bySession[s.id] ?? []
                return SessionTrendPoint(session: s, baseline: SessionSummary.baseline(of: a), graded: a.lazy.filter(\.isCounted).count)
            }
    }

    /// The most recent completed session's headline numbers, if any.
    func baselineOfLastCompletedSession(for deck: DeckID) async throws -> SessionBaseline? {
        guard let last = try await sessions(for: deck).last(where: { $0.status == .completed }) else { return nil }
        return SessionSummary.baseline(of: try await attempts(for: last.id))
    }
}

/// One completed session's headline numbers (trend charts, history rows).
public struct SessionTrendPoint: Sendable, Identifiable, Hashable {
    public let session: SessionRecord
    public let baseline: SessionBaseline
    /// Counted (non-retry, non-interrupted) attempts.
    public let graded: Int
    public var id: UUID { session.id }

    public init(session: SessionRecord, baseline: SessionBaseline, graded: Int) {
        self.session = session
        self.baseline = baseline
        self.graded = graded
    }
}

/// Everything stored, for export.
public struct ExportSnapshot: Codable, Sendable {
    /// 2 = optional `userDecks` (M4-8) and `personalSnippets` (M5 K4).
    public var schemaVersion = 2
    public let exportedAt: Date
    public let sessions: [SessionRecord]
    public let attempts: [Attempt]
    public let itemStats: [ItemStats]
    /// User-created decks, as data (backup only; there is no import).
    public var userDecks: [VocabDeckFile]?
    /// The user's own snippets keyed by entry id (M5 K4). Leave `nil` when there are none.
    public var personalSnippets: [String: PersonalSnippet]?

    public init(exportedAt: Date, sessions: [SessionRecord], attempts: [Attempt], itemStats: [ItemStats]) {
        self.exportedAt = exportedAt
        self.sessions = sessions
        self.attempts = attempts
        self.itemStats = itemStats
    }
}

/// Applies engine effects to a store strictly in order, off the caller's actor.
public final class SessionRecorder: Sendable {
    private let continuation: AsyncStream<SessionEffect>.Continuation
    private let task: Task<Void, Never>

    /// - Parameter onError: Called for every failed write (writes continue afterwards).
    public init(store: any StatsStore, onError: @escaping @Sendable (any Error) -> Void = { _ in }) {
        let (stream, continuation) = AsyncStream.makeStream(of: SessionEffect.self)
        self.continuation = continuation
        self.task = Task.detached(priority: .utility) {
            for await effect in stream {
                do { try await store.apply(effect) } catch { onError(error) }
            }
        }
    }

    public func record(_ effects: [SessionEffect]) {
        for e in effects { continuation.yield(e) }
    }

    /// Waits until every recorded effect has been written.
    public func close() async {
        continuation.finish()
        await task.value
    }

    deinit { continuation.finish() }
}
