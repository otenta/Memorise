#if DEBUG && targetEnvironment(simulator)
import Foundation
import MemoriseCore

/// Writes synthetic Fretboard history through the normal `StatsStore` API (performance measurement).
/// Compiled only into DEBUG simulator builds.
enum DevSeeder {
    /// 730 completed sessions × 40 attempts over the past year, deterministic (seeded).
    static func seedYear(store: any StatsStore, sessions: Int = 730, attemptsPerSession: Int = 40) async throws {
        let deck = FretboardNotesDeck()
        let cards = deck.cards(options: deck.defaultOptions)
        var rng = SplitMix64(seed: 0xC0FFEE)
        var stats: [ItemKey: ItemStats] = [:]
        let end = Date()
        let start = end.addingTimeInterval(-365 * 86_400)
        let step = (end.timeIntervalSince(start)) / Double(sessions)

        for s in 0..<sessions {
            let begin = start.addingTimeInterval(Double(s) * step)
            let config = SessionConfig.default(for: deck)
            var record = SessionRecord(id: UUID(), deckID: deck.id, startedAt: begin, status: .inProgress, config: config)
            try await store.upsert(record)
            var t = begin
            for i in 0..<attemptsPerSession {
                let card = cards[Int.random(in: 0..<cards.count, using: &rng)]
                let ms = Int.random(in: 600...6_000, using: &rng)
                let correct = Int.random(in: 0..<10, using: &rng) < 8
                let a = Attempt(
                    id: UUID(), sessionID: record.id, itemKey: card.key, deckID: deck.id, index: i, shownAt: t,
                    responseMs: ms, gradeMs: 400, correct: correct, isRetry: false, wasInterrupted: false
                )
                try await store.save(a)
                let updated = StatsUpdater.apply(a, at: t, to: stats[card.key] ?? .empty(key: card.key, deck: deck.id))
                stats[card.key] = updated
                t = t.addingTimeInterval(Double(ms + 400) / 1_000)
            }
            record.endedAt = t
            record.status = .completed
            try await store.upsert(record)
        }
        for s in stats.values { try await store.save(s) }
    }
}
#endif
