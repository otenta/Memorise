import Foundation
import MemoriseCore

/// Builds the SwiftData store off the main thread, runs the launch sweep, then forwards every call.
///
/// Every access awaits `ready`, so nothing touches the store before `closeInterruptedSessions()`
/// has finished. Falls back to an in-memory store (reported via `status`) if SwiftData fails.
final class DeferredStatsStore: StatsStore, Sendable {
    typealias Ready = (store: any StatsStore, persistent: Bool, error: String?)

    let ready: Task<Ready, Never>

    init() {
        ready = Task.detached(priority: .userInitiated) {
            let store: any StatsStore
            let persistent: Bool
            let failure: String?
            do {
                // Constructed inside the detached task so the model actor's executor is off-main.
                store = SwiftDataStatsStore(modelContainer: try SwiftDataStatsStore.makeContainer())
                persistent = true
                failure = nil
            } catch {
                AppEnvironment.log.fault("SwiftData unavailable, falling back to memory: \(error.localizedDescription, privacy: .public)")
                store = InMemoryStatsStore()
                persistent = false
                failure = error.localizedDescription
            }
            do {
                try await store.closeInterruptedSessions()
            } catch {
                AppEnvironment.log.error("Launch sweep failed: \(error.localizedDescription, privacy: .public)")
            }
            return (store, persistent, failure)
        }
    }

    /// Whether data is persisted, and the failure text when it isn't.
    var status: (persistent: Bool, error: String?) {
        get async {
            let r = await ready.value
            return (r.persistent, r.error)
        }
    }

    private var store: any StatsStore {
        get async { await ready.value.store }
    }

    func stats(for deck: DeckID) async throws -> [ItemKey: ItemStats] { try await store.stats(for: deck) }
    func save(_ stats: ItemStats) async throws { try await store.save(stats) }
    func save(_ attempt: Attempt) async throws { try await store.save(attempt) }
    func upsert(_ session: SessionRecord) async throws { try await store.upsert(session) }
    func sessions(for deck: DeckID) async throws -> [SessionRecord] { try await store.sessions(for: deck) }
    func attempts(for session: UUID) async throws -> [Attempt] { try await store.attempts(for: session) }
    func attempts(forDeck deck: DeckID) async throws -> [Attempt] { try await store.attempts(forDeck: deck) }
    func trendPoints(for deck: DeckID) async throws -> [SessionTrendPoint] { try await store.trendPoints(for: deck) }
    func closeInterruptedSessions() async throws { try await store.closeInterruptedSessions() }
    func reset(deck: DeckID) async throws { try await store.reset(deck: deck) }
    func resetAll() async throws { try await store.resetAll() }
    func exportSnapshot() async throws -> ExportSnapshot { try await store.exportSnapshot() }
}
