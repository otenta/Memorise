import Foundation
import MemoriseCore
import SwiftData

/// Version 1 of the on-device schema. Add `SchemaV2` + a migration stage for changes.
enum SchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }
    static var models: [any PersistentModel.Type] { [SDSession.self, SDAttempt.self, SDItemStats.self] }

    @Model
    final class SDSession {
        @Attribute(.unique) var id: UUID
        var deckID: String
        var startedAt: Date
        var endedAt: Date?
        var statusRaw: String
        /// JSON-encoded `SessionConfig` snapshot.
        var configData: Data

        init(id: UUID, deckID: String, startedAt: Date, endedAt: Date?, statusRaw: String, configData: Data) {
            self.id = id
            self.deckID = deckID
            self.startedAt = startedAt
            self.endedAt = endedAt
            self.statusRaw = statusRaw
            self.configData = configData
        }
    }

    @Model
    final class SDAttempt {
        @Attribute(.unique) var id: UUID
        var sessionID: UUID
        var itemKey: String
        var deckID: String
        var index: Int
        var shownAt: Date
        var responseMs: Int
        var gradeMs: Int
        var correct: Bool
        var isRetry: Bool
        var wasInterrupted: Bool

        init(_ a: Attempt) {
            id = a.id
            sessionID = a.sessionID
            itemKey = a.itemKey.raw
            deckID = a.deckID.raw
            index = a.index
            shownAt = a.shownAt
            responseMs = a.responseMs
            gradeMs = a.gradeMs
            correct = a.correct
            isRetry = a.isRetry
            wasInterrupted = a.wasInterrupted
        }
    }

    @Model
    final class SDItemStats {
        @Attribute(.unique) var itemKey: String
        var deckID: String
        var attempts: Int
        var correctCount: Int
        var ewmaResponseMs: Double?
        var ewmaError: Double
        var bestResponseMs: Int?
        var lastSeenAt: Date?
        var lastWrongAt: Date?

        init(_ s: ItemStats) {
            itemKey = s.itemKey.raw
            deckID = s.deckID.raw
            attempts = s.attempts
            correctCount = s.correctCount
            ewmaResponseMs = s.ewmaResponseMs
            ewmaError = s.ewmaError
            bestResponseMs = s.bestResponseMs
            lastSeenAt = s.lastSeenAt
            lastWrongAt = s.lastWrongAt
        }
    }
}

enum MemoriseMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [SchemaV1.self] }
    static var stages: [MigrationStage] { [] }
}

typealias SDSession = SchemaV1.SDSession
typealias SDAttempt = SchemaV1.SDAttempt
typealias SDItemStats = SchemaV1.SDItemStats

// MARK: - Mapping

extension SDItemStats {
    func update(from s: ItemStats) {
        deckID = s.deckID.raw
        attempts = s.attempts
        correctCount = s.correctCount
        ewmaResponseMs = s.ewmaResponseMs
        ewmaError = s.ewmaError
        bestResponseMs = s.bestResponseMs
        lastSeenAt = s.lastSeenAt
        lastWrongAt = s.lastWrongAt
    }

    var core: ItemStats {
        ItemStats(
            itemKey: ItemKey(itemKey), deckID: DeckID(deckID), attempts: attempts, correctCount: correctCount,
            ewmaResponseMs: ewmaResponseMs, ewmaError: ewmaError, bestResponseMs: bestResponseMs,
            lastSeenAt: lastSeenAt, lastWrongAt: lastWrongAt
        )
    }
}

extension SDAttempt {
    var core: Attempt {
        Attempt(
            id: id, sessionID: sessionID, itemKey: ItemKey(itemKey), deckID: DeckID(deckID), index: index,
            shownAt: shownAt, responseMs: responseMs, gradeMs: gradeMs, correct: correct,
            isRetry: isRetry, wasInterrupted: wasInterrupted
        )
    }
}

extension SDSession {
    /// Never drops a session: undecodable configs fall back to the deck's default options.
    func core(decoder: JSONDecoder) -> SessionRecord {
        let config: SessionConfig
        do {
            config = try decoder.decode(SessionConfig.self, from: configData)
        } catch {
            AppEnvironment.log.error("Session \(self.id.uuidString, privacy: .public): config decode failed (\(error.localizedDescription, privacy: .public)); using defaults")
            let deck = DeckID(deckID)
            config = SessionConfig(deckID: deck, options: .fallback(for: deck))
        }
        if !config.recoveredFields.isEmpty {
            AppEnvironment.log.error("Session \(self.id.uuidString, privacy: .public): recovered fields \(config.recoveredFields.sorted().joined(separator: ","), privacy: .public)")
        }
        return SessionRecord(
            id: id, deckID: DeckID(deckID), startedAt: startedAt, endedAt: endedAt,
            status: SessionStatus(rawValue: statusRaw) ?? .abandoned, config: config
        )
    }
}
