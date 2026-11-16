import Foundation
import Testing
@testable import MemoriseCore

/// PLAN §9.5 session summary, F9 P4-b (clamped fastest/slowest).
@Suite("Session summary (§9.5)")
struct SessionSummaryTests {
    let sid = UUID()
    var record: SessionRecord {
        SessionRecord(id: sid, deckID: "d", startedAt: fixedNow, endedAt: fixedNow.addingTimeInterval(90), status: .completed,
                      config: SessionConfig(deckID: "d", options: .fretboard(FretboardOptions())))
    }

    @Test func countsTimingsAndLists() {
        let attempts = [
            attempt(session: sid, key: "a", index: 0, responseMs: 1_000),
            attempt(session: sid, key: "b", index: 1, responseMs: 3_000, correct: false),
            attempt(session: sid, key: "c", index: 2, responseMs: 2_000),
            attempt(session: sid, key: "d", index: 3, responseMs: 500, interrupted: true),
            attempt(session: sid, key: "d", index: 4, responseMs: 4_000),
            attempt(session: sid, key: "b", index: 5, responseMs: 100, isRetry: true),
            attempt(session: sid, key: "b", index: 6, responseMs: 5_000, correct: false),
        ]
        var rng = SplitMix64(seed: 123)
        let s = SessionSummary.build(session: record, attempts: attempts.shuffled(using: &rng), priorEwma: ["a": 2_000])
        #expect(s.gradedCount == 5)
        #expect(s.correctCount == 3)
        #expect(s.wrongCount == 2)
        #expect(s.accuracy == 0.6)
        #expect(s.medianMs == 2_000)
        #expect(s.meanMs == (1_000.0 + 2_000 + 4_000) / 3)
        #expect(abs(s.p90Ms! - 3_600) < 1e-9)
        #expect(s.fastest?.itemKey == "a")
        #expect(s.slowest?.itemKey == "d")
        #expect(s.rows.map(\.index) == [0, 1, 2, 4, 5, 6], "rows in order, interrupted excluded, retries kept")
        #expect(s.rows.first { $0.isRetry }?.itemKey == "b")
        #expect(s.slowest5.map(\.itemKey) == ["d", "c", "a"])
        #expect(s.wrong.map(\.itemKey) == ["b"], "one wrong row per item")
        #expect(s.totalDuration == 90)
        #expect(s.rows[0].ratioToHistory == 0.5)
        #expect(s.rows[1].ratioToHistory == nil, "wrong rows are not compared")
    }

    @Test func slowest5CapsAtFive() {
        let attempts = (0..<8).map { attempt(session: sid, key: ItemKey("k\($0)"), index: $0, responseMs: 1_000 + $0 * 100) }
        let s = SessionSummary.build(session: record, attempts: attempts)
        #expect(s.slowest5.map(\.responseMs) == [1_700, 1_600, 1_500, 1_400, 1_300])
    }

    @Test func emptySessionHasNoNumbers() {
        let s = SessionSummary.build(session: record, attempts: [])
        #expect(s.gradedCount == 0)
        #expect(s.accuracy == nil && s.medianMs == nil && s.meanMs == nil && s.fastest == nil)
        #expect(s.medianDeltaMs == nil && s.accuracyDelta == nil)
    }

    /// P4-b: one attempt at 40 000 ms is clamped to 30 000 everywhere in the maths.
    @Test func clampedFastestSlowestAndStats() {
        let attempts = [
            attempt(session: sid, key: "long", index: 0, responseMs: 40_000),
            attempt(session: sid, key: "cap", index: 1, responseMs: 30_000),
            attempt(session: sid, key: "tiny", index: 2, responseMs: 50),
            attempt(session: sid, key: "small", index: 3, responseMs: 150),
        ]
        let s = SessionSummary.build(session: record, attempts: attempts)
        #expect(s.meanMs == (30_000.0 + 30_000 + 150 + 150) / 4)
        #expect(s.fastest?.itemKey == "tiny", "ties on the clamped value keep session order")
        #expect(s.slowest?.itemKey == "cap", "40 000 and 30 000 tie at the clamp; stable order")
        #expect(s.rows[0].responseMs == 40_000, "raw value kept in rows")
    }

    @Test func comparisonWithPreviousSession() {
        let attempts = [attempt(session: sid, key: "a", index: 0, responseMs: 1_500), attempt(session: sid, key: "b", index: 1, correct: false)]
        let s = SessionSummary.build(session: record, attempts: attempts, previous: SessionBaseline(medianMs: 2_000, accuracy: 0.75))
        #expect(s.medianDeltaMs == -500)
        #expect(s.medianDeltaPercent == -0.25)
        #expect(s.accuracyDelta == -0.25)
        #expect(s.baseline == SessionBaseline(medianMs: 1_500, accuracy: 0.5))
    }

    @Test func baselineOfAttempts() {
        let b = SessionSummary.baseline(of: [
            attempt(session: sid, index: 0, responseMs: 100),
            attempt(session: sid, index: 1, responseMs: 2_000),
            attempt(session: sid, index: 2, correct: false),
            attempt(session: sid, index: 3, isRetry: true),
            attempt(session: sid, index: 4, interrupted: true),
        ])
        #expect(b.accuracy == 2.0 / 3.0)
        #expect(b.medianMs == (150.0 + 2_000) / 2)
        #expect(SessionSummary.baseline(of: []) == SessionBaseline(medianMs: nil, accuracy: nil))
    }

    @Test func liveSummaryMatchesSummaryRebuiltFromStoredAttempts() {
        let (e, clock) = makeEngine(seed: 21)
        _ = e.start()
        var i = 0
        driveUntilFinished(e, clock: clock) { _ in i += 1; return i % 4 != 0 }
        guard let live = e.state.summary else { Issue.record("not finished"); return }
        let rebuilt = SessionSummary.build(session: e.record, attempts: e.attempts)
        #expect(rebuilt.gradedCount == live.gradedCount)
        #expect(rebuilt.medianMs == live.medianMs)
        #expect(rebuilt.rows.map(\.attemptID) == live.rows.map(\.attemptID))
        #expect(live.rows.allSatisfy { $0.card != nil }, "live summary resolves cards")
    }
}
