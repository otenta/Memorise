import Foundation

/// Non-persistent store for tests and previews.
public actor InMemoryStatsStore: StatsStore {
    private var itemStats: [ItemKey: ItemStats] = [:]
    private var sessionsByID: [UUID: SessionRecord] = [:]
    private var attemptsBySession: [UUID: [Attempt]] = [:]
    private let now: @Sendable () -> Date

    public init(
        stats: [ItemStats] = [],
        sessions: [SessionRecord] = [],
        attempts: [Attempt] = [],
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.now = now
        for s in stats { itemStats[s.itemKey] = s }
        for s in sessions { sessionsByID[s.id] = s }
        for a in attempts { attemptsBySession[a.sessionID, default: []].append(a) }
    }

    public func stats(for deck: DeckID) -> [ItemKey: ItemStats] {
        itemStats.filter { $0.value.deckID == deck }
    }

    public func save(_ stats: ItemStats) { itemStats[stats.itemKey] = stats }

    public func save(_ attempt: Attempt) {
        attemptsBySession[attempt.sessionID, default: []].append(attempt)
    }

    public func upsert(_ session: SessionRecord) { sessionsByID[session.id] = session }

    public func sessions(for deck: DeckID) -> [SessionRecord] {
        sessionsByID.values.filter { $0.deckID == deck }.sorted { $0.startedAt < $1.startedAt }
    }

    public func attempts(for session: UUID) -> [Attempt] {
        (attemptsBySession[session] ?? []).sorted { $0.index < $1.index }
    }

    public func attempts(forDeck deck: DeckID) -> [Attempt] {
        attemptsBySession.values.lazy.joined()
            .filter { $0.deckID == deck }
            .sorted { ($0.shownAt, $0.index) < ($1.shownAt, $1.index) }
    }

    public func closeInterruptedSessions() {
        for (id, s) in sessionsByID where s.status == .inProgress {
            sessionsByID[id] = s.closedAfterInterruption(attempts: attemptsBySession[id] ?? [])
        }
    }

    public func discard(session: UUID, restore: [ItemStats], delete: [ItemKey], deck: DeckID) {
        sessionsByID[session] = nil
        attemptsBySession[session] = nil
        for s in restore { itemStats[s.itemKey] = s }
        for key in delete where itemStats[key]?.deckID == deck { itemStats[key] = nil }
    }

    public func reset(deck: DeckID) {
        itemStats = itemStats.filter { $0.value.deckID != deck }
        for s in sessionsByID.values where s.deckID == deck {
            sessionsByID[s.id] = nil
            attemptsBySession[s.id] = nil
        }
    }

    public func resetAll() {
        itemStats.removeAll()
        sessionsByID.removeAll()
        attemptsBySession.removeAll()
    }

    public func exportSnapshot() -> ExportSnapshot {
        let sessions = sessionsByID.values.sorted { $0.startedAt < $1.startedAt }
        return ExportSnapshot(
            exportedAt: now(),
            sessions: sessions,
            attempts: sessions.flatMap { attempts(for: $0.id) },
            itemStats: itemStats.values.sorted { $0.itemKey < $1.itemKey }
        )
    }
}
