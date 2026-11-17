import Foundation
import MemoriseCore
import SwiftData

/// SwiftData-backed `StatsStore`, isolated on its own model actor. Every write is saved immediately.
@ModelActor
actor SwiftDataStatsStore: StatsStore {
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    /// Creates the on-disk (or in-memory) container.
    static func makeContainer(inMemory: Bool = false) throws -> ModelContainer {
        try ModelContainer(
            for: Schema(versionedSchema: SchemaV1.self),
            migrationPlan: MemoriseMigrationPlan.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: inMemory)
        )
    }

    // MARK: Reads

    func stats(for deck: DeckID) throws -> [ItemKey: ItemStats] {
        let raw = deck.raw
        let rows = try modelContext.fetch(FetchDescriptor<SDItemStats>(predicate: #Predicate { $0.deckID == raw }))
        var result = [ItemKey: ItemStats](minimumCapacity: rows.count)
        for r in rows { result[ItemKey(r.itemKey)] = r.core }
        return result
    }

    func stats(forDecks decks: [DeckID]) throws -> [DeckID: [ItemKey: ItemStats]] {
        var result = [DeckID: [ItemKey: ItemStats]](minimumCapacity: decks.count)
        for deck in decks { result[deck] = [:] }
        guard !decks.isEmpty else { return result }
        let raws = decks.map(\.raw)
        let rows = try modelContext.fetch(FetchDescriptor<SDItemStats>(predicate: #Predicate { raws.contains($0.deckID) }))
        for r in rows { result[DeckID(r.deckID), default: [:]][ItemKey(r.itemKey)] = r.core }
        return result
    }

    func sessions(for deck: DeckID) throws -> [SessionRecord] {
        let raw = deck.raw
        let rows = try modelContext.fetch(FetchDescriptor<SDSession>(
            predicate: #Predicate { $0.deckID == raw },
            sortBy: [SortDescriptor(\.startedAt)]
        ))
        return rows.map { $0.core(decoder: decoder) }
    }

    func attempts(for session: UUID) throws -> [Attempt] {
        try modelContext.fetch(FetchDescriptor<SDAttempt>(
            predicate: #Predicate { $0.sessionID == session },
            sortBy: [SortDescriptor(\.index)]
        )).map(\.core)
    }

    func attempts(forDeck deck: DeckID) throws -> [Attempt] {
        let raw = deck.raw
        return try modelContext.fetch(FetchDescriptor<SDAttempt>(
            predicate: #Predicate { $0.deckID == raw },
            sortBy: [SortDescriptor(\.shownAt), SortDescriptor(\.index)]
        )).map(\.core)
    }

    func exportSnapshot() throws -> ExportSnapshot {
        let sessions = try modelContext.fetch(FetchDescriptor<SDSession>(sortBy: [SortDescriptor(\.startedAt)]))
            .map { $0.core(decoder: decoder) }
        let attempts = try modelContext.fetch(FetchDescriptor<SDAttempt>(sortBy: [SortDescriptor(\.shownAt), SortDescriptor(\.index)]))
            .map(\.core)
        let stats = try modelContext.fetch(FetchDescriptor<SDItemStats>(sortBy: [SortDescriptor(\.itemKey)]))
            .map(\.core)
        return ExportSnapshot(exportedAt: Date(), sessions: sessions, attempts: attempts, itemStats: stats)
    }

    // MARK: Writes

    func save(_ stats: ItemStats) throws {
        let key = stats.itemKey.raw
        var descriptor = FetchDescriptor<SDItemStats>(predicate: #Predicate { $0.itemKey == key })
        descriptor.fetchLimit = 1
        if let existing = try modelContext.fetch(descriptor).first {
            existing.update(from: stats)
        } else {
            modelContext.insert(SDItemStats(stats))
        }
        try modelContext.save()
    }

    func save(_ attempt: Attempt) throws {
        modelContext.insert(SDAttempt(attempt))
        try modelContext.save()
    }

    func upsert(_ session: SessionRecord) throws {
        let id = session.id
        var descriptor = FetchDescriptor<SDSession>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        if let existing = try modelContext.fetch(descriptor).first {
            existing.endedAt = session.endedAt
            existing.statusRaw = session.status.rawValue
        } else {
            modelContext.insert(SDSession(
                id: session.id, deckID: session.deckID.raw, startedAt: session.startedAt, endedAt: session.endedAt,
                statusRaw: session.status.rawValue, configData: try encoder.encode(session.config)
            ))
        }
        try modelContext.save()
    }

    func closeInterruptedSessions() throws {
        let raw = SessionStatus.inProgress.rawValue
        let rows = try modelContext.fetch(FetchDescriptor<SDSession>(predicate: #Predicate { $0.statusRaw == raw }))
        guard !rows.isEmpty else { return }
        for row in rows {
            let closed = row.core(decoder: decoder).closedAfterInterruption(attempts: try attempts(for: row.id))
            row.statusRaw = closed.status.rawValue
            row.endedAt = closed.endedAt
        }
        try modelContext.save()
    }

    func discard(session: UUID, restore: [ItemStats], delete: [ItemKey], deck: DeckID) throws {
        try modelContext.delete(model: SDAttempt.self, where: #Predicate { $0.sessionID == session })
        try modelContext.delete(model: SDSession.self, where: #Predicate { $0.id == session })
        if !restore.isEmpty {
            let keys = restore.map(\.itemKey.raw)
            let rows = try modelContext.fetch(FetchDescriptor<SDItemStats>(predicate: #Predicate { keys.contains($0.itemKey) }))
            var byKey = [String: SDItemStats](minimumCapacity: rows.count)
            for r in rows { byKey[r.itemKey] = r }
            for s in restore {
                if let row = byKey[s.itemKey.raw] { row.update(from: s) } else { modelContext.insert(SDItemStats(s)) }
            }
        }
        if !delete.isEmpty {
            let keys = delete.map(\.raw)
            let raw = deck.raw
            try modelContext.delete(model: SDItemStats.self, where: #Predicate { $0.deckID == raw && keys.contains($0.itemKey) })
        }
        try modelContext.save()
    }

    func reset(deck: DeckID) throws {
        let raw = deck.raw
        try modelContext.delete(model: SDItemStats.self, where: #Predicate { $0.deckID == raw })
        try modelContext.delete(model: SDAttempt.self, where: #Predicate { $0.deckID == raw })
        try modelContext.delete(model: SDSession.self, where: #Predicate { $0.deckID == raw })
        try modelContext.save()
    }

    func resetAll() throws {
        try modelContext.delete(model: SDItemStats.self)
        try modelContext.delete(model: SDAttempt.self)
        try modelContext.delete(model: SDSession.self)
        try modelContext.save()
    }
}
