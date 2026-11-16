import Foundation
import Testing
@testable import MemoriseCore

/// Fixed wall-clock origin. No test depends on the real date (PLAN §13 determinism rule).
let fixedNow = Date(timeIntervalSince1970: 1_800_000_000)

/// Engine + manual clock, where the wall clock advances along with the monotonic clock.
func makeEngine(
    deck: any Deck = FretboardNotesDeck(),
    config: SessionConfig? = nil,
    stats: [ItemKey: ItemStats] = [:],
    previous: SessionBaseline? = nil,
    seed: UInt64 = 1,
    constants: SchedulerConstants = .standard
) -> (SessionEngine, ManualClock) {
    let clock = ManualClock()
    let engine = SessionEngine(
        deck: deck,
        config: config ?? .default(for: deck),
        stats: stats,
        previous: previous,
        clock: clock,
        rng: SplitMix64(seed: seed),
        sessionID: UUID(),
        wallClock: { fixedNow.addingTimeInterval(Double(clock.now().wholeMilliseconds) / 1_000) },
        constants: constants
    )
    return (engine, clock)
}

func fretboardCards(_ options: FretboardOptions = FretboardOptions()) -> [Card] {
    FretboardNotesDeck().cards(options: .fretboard(options))
}

/// Drives one card per grade: appear → wait `response` → OK → wait `gradeDelay` (> lockout) → grade.
/// Stops early when the session finishes. Returns every emitted effect.
@discardableResult
func drive(
    _ engine: SessionEngine,
    clock: ManualClock,
    grades: [Bool],
    response: Duration = .milliseconds(1_000),
    gradeDelay: Duration = .milliseconds(300)
) -> [SessionEffect] {
    var effects: [SessionEffect] = []
    for g in grades {
        guard case .prompting = engine.state else { break }
        engine.promptDidAppear()
        clock.advance(by: response)
        engine.ok()
        clock.advance(by: gradeDelay)
        effects += engine.grade(correct: g)
    }
    return effects
}

/// Grades every card with `grade(card)` until the session finishes (safety cap).
@discardableResult
func driveUntilFinished(
    _ engine: SessionEngine,
    clock: ManualClock,
    cap: Int = 1_000,
    grade: (PresentedCard) -> Bool
) -> [SessionEffect] {
    var effects: [SessionEffect] = []
    var n = 0
    while case let .prompting(p) = engine.state, n < cap {
        engine.promptDidAppear()
        clock.advance(by: .milliseconds(1_000))
        engine.ok()
        clock.advance(by: .milliseconds(300))
        effects += engine.grade(correct: grade(p))
        n += 1
    }
    return effects
}

extension SessionEffect {
    var attempt: Attempt? { if case let .saveAttempt(a) = self { a } else { nil } }
    var itemStats: ItemStats? { if case let .saveStats(s) = self { s } else { nil } }
    var session: SessionRecord? { if case let .upsertSession(s) = self { s } else { nil } }
}

extension SessionState {
    var isFinished: Bool { if case .finished = self { true } else { false } }
    var summary: SessionSummary? { if case let .finished(s) = self { s } else { nil } }
    var isRevealed: Bool { if case .revealed = self { true } else { false } }
}

// MARK: - Synthetic vocab content

/// `"<prefix>.0042"` (Linux-safe, no `String(format:)`).
func entryID(_ n: Int, prefix: String = "ko.test") -> String {
    let digits = String(n)
    return prefix + "." + String(repeating: "0", count: max(0, 4 - digits.count)) + digits
}

func vocabEntry(_ n: Int, prefix: String = "ko.test", tags: [String] = [], pos: String = "noun", hangul: String = "사람") -> VocabEntry {
    VocabEntry(
        id: entryID(n, prefix: prefix), hangul: hangul, romanization: "saram",
        meanings: ["person \(n)"], pos: pos, rank: n, tags: tags
    )
}

func vocabFile(count: Int, deckId: String = "ko.test.1", prefix: String = "ko.test", tags: (Int) -> [String] = { _ in [] }) -> VocabDeckFile {
    VocabDeckFile(
        deckId: deckId, title: "Test", subtitle: "", subject: .korean,
        entries: (1...count).map { vocabEntry($0, prefix: prefix, tags: tags($0)) }
    )
}

func vocabDeck(count: Int, tags: (Int) -> [String] = { _ in [] }) -> VocabDeck {
    VocabDeck(file: vocabFile(count: count, tags: tags))
}

/// Stats for a card that has been seen (`attempts > 0`).
func seenStats(_ key: ItemKey, deck: DeckID = FretboardNotesDeck.deckID, ewma: Double? = 2_000, error: Double = 0, attempts: Int = 5, lastSeen: Date? = fixedNow) -> ItemStats {
    ItemStats(itemKey: key, deckID: deck, attempts: attempts, correctCount: attempts, ewmaResponseMs: ewma,
              ewmaError: error, bestResponseMs: ewma.map { Int($0) }, lastSeenAt: lastSeen)
}

func attempt(
    session: UUID, key: ItemKey = "k", deck: DeckID = "d", index: Int, shownAt: Date = fixedNow,
    responseMs: Int = 1_000, gradeMs: Int = 200, correct: Bool = true, isRetry: Bool = false, interrupted: Bool = false
) -> Attempt {
    Attempt(id: UUID(), sessionID: session, itemKey: key, deckID: deck, index: index, shownAt: shownAt,
            responseMs: responseMs, gradeMs: gradeMs, correct: correct, isRetry: isRetry, wasInterrupted: interrupted)
}
