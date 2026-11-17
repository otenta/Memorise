import Foundation
import Testing
@testable import MemoriseCore

/// PLAN §6.4/§9.3 #3 (persistence), F6 (closeInterruptedSessions), F7 (trendPoints, ordering), exporter.
@Suite("Persistence & integration (F6, F7)")
struct PersistenceTests {
    let deck: DeckID = "music.fretboard.notes"
    let config = SessionConfig(deckID: "music.fretboard.notes", options: .fretboard(FretboardOptions()))

    private func session(_ id: UUID = UUID(), start: TimeInterval, status: SessionStatus, deck: DeckID? = nil) -> SessionRecord {
        SessionRecord(id: id, deckID: deck ?? self.deck, startedAt: fixedNow.addingTimeInterval(start), status: status, config: config)
    }

    // MARK: F6 — interrupted sessions

    @Test func killedSessionWithCountedAttemptsBecomesCompleted() async throws {
        let s = session(start: 0, status: .inProgress)
        let a1 = attempt(session: s.id, deck: deck, index: 0, shownAt: fixedNow.addingTimeInterval(1), responseMs: 1_000, gradeMs: 500)
        let a2 = attempt(session: s.id, deck: deck, index: 1, shownAt: fixedNow.addingTimeInterval(10), responseMs: 2_000, gradeMs: 250)
        let store: any StatsStore = InMemoryStatsStore(sessions: [s], attempts: [a1, a2])
        try await store.closeInterruptedSessions()
        let closed = try await store.sessions(for: deck)[0]
        #expect(closed.status == .completed)
        #expect(closed.endedAt == fixedNow.addingTimeInterval(12.25))
        #expect(closed.duration == 12.25)
    }

    @Test func killedSessionWithOnlyInterruptedAttemptsBecomesAbandoned() async throws {
        let s = session(start: 0, status: .inProgress)
        let a = attempt(session: s.id, deck: deck, index: 0, shownAt: fixedNow.addingTimeInterval(4), interrupted: true)
        let empty = session(start: 100, status: .inProgress)
        let done = SessionRecord(id: UUID(), deckID: deck, startedAt: fixedNow.addingTimeInterval(200), endedAt: fixedNow.addingTimeInterval(260), status: .completed, config: config)
        let store: any StatsStore = InMemoryStatsStore(sessions: [s, empty, done], attempts: [a])
        try await store.closeInterruptedSessions()
        let all = try await store.sessions(for: deck)
        #expect(all[0].status == .abandoned)
        #expect(all[0].endedAt == fixedNow.addingTimeInterval(4))
        #expect(all[1].status == .abandoned)
        #expect(all[1].endedAt == all[1].startedAt)
        #expect(all[2] == done, "finished sessions untouched")
    }

    // MARK: F7 — trend points & ordering

    @Test func trendPointsOnlyCompletedOrderedByStartWithCountedGraded() async throws {
        let late = session(start: 500, status: .completed)
        let early = session(start: 0, status: .completed)
        let abandoned = session(start: 200, status: .abandoned)
        let other = session(start: 50, status: .completed, deck: "ko.core.1")
        let attempts = [
            attempt(session: early.id, deck: deck, index: 0, responseMs: 1_000),
            attempt(session: early.id, deck: deck, index: 1, correct: false),
            attempt(session: early.id, deck: deck, index: 2, isRetry: true),
            attempt(session: early.id, deck: deck, index: 3, interrupted: true),
            attempt(session: late.id, deck: deck, index: 0, responseMs: 3_000),
            attempt(session: abandoned.id, deck: deck, index: 0),
            attempt(session: other.id, deck: "ko.core.1", index: 0),
        ]
        let store: any StatsStore = InMemoryStatsStore(sessions: [late, early, abandoned, other], attempts: attempts)
        let points = try await store.trendPoints(for: deck)
        #expect(points.map(\.id) == [early.id, late.id])
        #expect(points[0].graded == 2)
        #expect(points[0].baseline == SessionBaseline(medianMs: 1_000, accuracy: 0.5))
        #expect(points[1].baseline.medianMs == 3_000)
        let baseline = try await store.baselineOfLastCompletedSession(for: deck)
        #expect(baseline?.medianMs == 3_000)
        #expect(try await store.baselineOfLastCompletedSession(for: "nothing") == nil)
    }

    @Test func attemptsForDeckOrderedByShownAtThenIndex() async throws {
        let s1 = UUID(), s2 = UUID()
        let t = fixedNow
        let store: any StatsStore = InMemoryStatsStore(attempts: [
            attempt(session: s2, deck: deck, index: 1, shownAt: t.addingTimeInterval(5)),
            attempt(session: s1, deck: deck, index: 3, shownAt: t),
            attempt(session: s2, deck: deck, index: 0, shownAt: t.addingTimeInterval(5)),
            attempt(session: s1, deck: deck, index: 2, shownAt: t),
            attempt(session: UUID(), deck: "other", index: 0, shownAt: t),
        ])
        let a = try await store.attempts(forDeck: deck)
        #expect(a.map(\.index) == [2, 3, 0, 1])
        #expect(try await store.attempts(for: s1).map(\.index) == [2, 3])
    }

    @Test func resetAndExport() async throws {
        let s1 = session(start: 0, status: .completed)
        let s2 = session(start: 10, status: .completed, deck: "ko.core.1")
        let store: any StatsStore = InMemoryStatsStore(
            stats: [seenStats("fret:s6:A"), seenStats("ko.core.0001#ko-en", deck: "ko.core.1")],
            sessions: [s1, s2],
            attempts: [attempt(session: s1.id, deck: deck, index: 0), attempt(session: s2.id, deck: "ko.core.1", index: 0)],
            now: { fixedNow }
        )
        try await store.reset(deck: deck)
        #expect(try await store.stats(for: deck).isEmpty)
        #expect(try await store.sessions(for: deck).isEmpty)
        #expect(try await store.attempts(for: s1.id).isEmpty)
        let snap = try await store.exportSnapshot()
        #expect(snap.sessions.map(\.id) == [s2.id])
        #expect(snap.attempts.count == 1)
        #expect(snap.itemStats.count == 1)
        #expect(snap.exportedAt == fixedNow)
        try await store.resetAll()
        let empty = try await store.exportSnapshot()
        #expect(empty.sessions.isEmpty && empty.attempts.isEmpty && empty.itemStats.isEmpty)
    }

    // MARK: Engine → recorder → store integration

    @Test func fullSessionPersistsThroughRecorder() async throws {
        let store: any StatsStore = InMemoryStatsStore()
        let errors = ErrorCounter()
        let recorder = SessionRecorder(store: store) { _ in errors.increment() }
        let (e, clock) = makeEngine(seed: 4)
        recorder.record(e.start())
        var i = 0
        while case .prompting = e.state, i < 100 {
            i += 1
            e.promptDidAppear()
            clock.advance(by: .milliseconds(800 + i * 10))
            e.ok()
            clock.advance(by: .milliseconds(300))
            recorder.record(e.grade(correct: i % 5 != 0))
        }
        await recorder.close()
        #expect(errors.value == 0)

        let sessions = try await store.sessions(for: e.deck.id)
        #expect(sessions.count == 1)
        #expect(sessions[0].status == .completed)
        #expect(try await store.attempts(for: e.record.id).count == e.attempts.count)
        #expect(try await store.stats(for: e.deck.id) == e.stats)
        let point = try await store.trendPoints(for: e.deck.id).first
        #expect(point?.baseline == e.state.summary?.baseline)
        #expect(point?.graded == 20)
    }

    @Test func killMidSessionThenLaunchSweep() async throws {
        let store: any StatsStore = InMemoryStatsStore()
        let (e, clock) = makeEngine(seed: 9)
        for effect in e.start() { try await store.apply(effect) }
        for effect in drive(e, clock: clock, grades: [true, false, true]) { try await store.apply(effect) }
        for effect in e.pause() { try await store.apply(effect) } // app backgrounded, then killed
        #expect(try await store.sessions(for: e.deck.id).first?.status == .inProgress)

        try await store.closeInterruptedSessions()
        let s = try await store.sessions(for: e.deck.id)[0]
        #expect(s.status == .completed)
        #expect(s.duration > 0)
        #expect(try await store.trendPoints(for: e.deck.id).first?.graded == 3)
    }

    @Test func recorderReportsErrorsAndKeepsWriting() async {
        let store = FailingStore(failEvery: 2)
        let errors = ErrorCounter()
        let recorder = SessionRecorder(store: store) { _ in errors.increment() }
        let s = session(start: 0, status: .inProgress)
        recorder.record((0..<6).map { .saveAttempt(attempt(session: s.id, index: $0)) })
        await recorder.close()
        #expect(errors.value == 3)
        #expect(await store.writes == 6)
    }

    // MARK: Exporter

    @Test func csvFormat() {
        let sid = UUID()
        let a = attempt(session: sid, key: "ko.x.0001#ko-en", deck: "ko.x", index: 0, shownAt: fixedNow, responseMs: 1_234, gradeMs: 56, correct: false, isRetry: true)
        let csv = Exporter.csv([a])
        let lines = csv.components(separatedBy: "\r\n")
        #expect(lines[0] == Exporter.csvHeader)
        #expect(lines[1] == "\(sid.uuidString),ko.x,0,ko.x.0001#ko-en,2027-01-15T08:00:00Z,1234,56,0,1,0")
        #expect(lines.count == 3 && lines[2].isEmpty, "CRLF-terminated")
        #expect(Exporter.csv([]) == Exporter.csvHeader + "\r\n")
    }

    @Test func csvEscaping() {
        #expect(Exporter.escape("plain") == "plain")
        #expect(Exporter.escape("a,b") == "\"a,b\"")
        #expect(Exporter.escape("say \"hi\"") == "\"say \"\"hi\"\"\"")
        #expect(Exporter.escape("line\nbreak") == "\"line\nbreak\"")
    }

    @Test func jsonExportRoundTrips() throws {
        let s = session(start: 0, status: .completed)
        let snap = ExportSnapshot(exportedAt: fixedNow, sessions: [s], attempts: [attempt(session: s.id, deck: deck, index: 0)], itemStats: [seenStats("fret:s6:A")])
        let data = try Exporter.json(snap)
        let text = String(decoding: data, as: UTF8.self)
        #expect(text.contains("\"schemaVersion\" : 2"))
        #expect(text.contains("2027-01-15T08:00:00Z"))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let back = try decoder.decode(ExportSnapshot.self, from: data)
        #expect(back.sessions == snap.sessions)
        #expect(back.attempts == snap.attempts)
        #expect(back.itemStats == snap.itemStats)
    }
}

final class ErrorCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var n = 0
    func increment() { lock.lock(); n += 1; lock.unlock() }
    var value: Int { lock.lock(); defer { lock.unlock() }; return n }
}

/// Store whose every `failEvery`-th attempt write throws.
actor FailingStore: StatsStore {
    let failEvery: Int
    private(set) var writes = 0
    init(failEvery: Int) { self.failEvery = failEvery }
    struct Boom: Error {}
    func save(_ attempt: Attempt) throws {
        writes += 1
        if writes % failEvery == 0 { throw Boom() }
    }
    func stats(for deck: DeckID) -> [ItemKey: ItemStats] { [:] }
    func save(_ stats: ItemStats) {}
    func upsert(_ session: SessionRecord) {}
    func sessions(for deck: DeckID) -> [SessionRecord] { [] }
    func attempts(for session: UUID) -> [Attempt] { [] }
    func attempts(forDeck deck: DeckID) -> [Attempt] { [] }
    func closeInterruptedSessions() {}
    func reset(deck: DeckID) {}
    func resetAll() {}
    func exportSnapshot() -> ExportSnapshot { ExportSnapshot(exportedAt: fixedNow, sessions: [], attempts: [], itemStats: []) }
}
