import Foundation
import Testing
@testable import MemoriseCore

/// PLAN §9.1–§9.3 session engine, F3 (retry/fallback order), F4 (grade lockout).
@Suite("Session engine (§9.3)")
struct SessionEngineTests {
    // MARK: Lifecycle & timing

    @Test func startEmitsInProgressSessionAndPrompts() {
        let (e, _) = makeEngine()
        let effects = e.start()
        #expect(effects.count == 1)
        #expect(effects.first?.session?.status == .inProgress)
        guard case .prompting = e.state else { Issue.record("expected prompting"); return }
        #expect(e.start().isEmpty, "start is idempotent")
        #expect(e.poolSize == 42)
    }

    @Test func responseTimeRunsFromPromptAppearToOk() {
        let (e, clock) = makeEngine()
        _ = e.start()
        clock.advance(by: .milliseconds(500)) // transition before the prompt is visible — not counted
        e.promptDidAppear()
        clock.advance(by: .milliseconds(1_234))
        #expect(e.currentPromptElapsed == .milliseconds(1_234))
        e.ok()
        guard case let .revealed(_, ms) = e.state else { Issue.record("expected revealed"); return }
        #expect(ms == 1_234)
        #expect(e.currentPromptElapsed == nil)
    }

    @Test func okWithoutPromptDidAppearFallsBackToSelectionTime() {
        let (e, clock) = makeEngine()
        _ = e.start()
        clock.advance(by: .milliseconds(800))
        e.ok()
        guard case let .revealed(_, ms) = e.state else { Issue.record("expected revealed"); return }
        #expect(ms == 800)
    }

    @Test func gradeEmitsAttemptThenStatsWithTimings() {
        let (e, clock) = makeEngine()
        _ = e.start()
        let effects = drive(e, clock: clock, grades: [true], response: .milliseconds(1_500), gradeDelay: .milliseconds(400))
        #expect(effects.count == 2)
        let a = effects[0].attempt!
        #expect(a.responseMs == 1_500)
        #expect(a.gradeMs == 400)
        #expect(a.correct && !a.isRetry && !a.wasInterrupted)
        #expect(a.index == 0)
        #expect(a.sessionID == e.record.id)
        let s = effects[1].itemStats!
        #expect(s.itemKey == a.itemKey)
        #expect(s.attempts == 1)
        #expect(e.stats[a.itemKey] == s)
    }

    @Test func finishesAfterNCountedCards() {
        let config = SessionConfig(deckID: FretboardNotesDeck.deckID, options: .fretboard(FretboardOptions()), length: .cards(10))
        let (e, clock) = makeEngine(config: config)
        _ = e.start()
        let effects = driveUntilFinished(e, clock: clock) { _ in true }
        #expect(e.state.isFinished)
        #expect(e.countedGraded == 10)
        #expect(e.progress == 1)
        #expect(effects.last?.session?.status == .completed)
        #expect(e.state.summary?.gradedCount == 10)
        #expect(e.record.endedAt != nil)
    }

    @Test func progressTracksCountedCards() {
        let config = SessionConfig(deckID: FretboardNotesDeck.deckID, options: .fretboard(FretboardOptions()), length: .cards(4))
        let (e, clock) = makeEngine(config: config)
        _ = e.start()
        #expect(e.progress == 0)
        drive(e, clock: clock, grades: [true])
        #expect(e.progress == 0.25)
    }

    @Test func quitWithNothingGradedIsAbandoned() {
        let (e, _) = makeEngine()
        _ = e.start()
        let effects = e.quit()
        #expect(effects.first?.session?.status == .abandoned)
        #expect(e.state.isFinished)
        #expect(e.quit().isEmpty)
    }

    @Test func quitAfterGradingIsCompleted() {
        let (e, clock) = makeEngine()
        _ = e.start()
        drive(e, clock: clock, grades: [true, false])
        #expect(e.quit().first?.session?.status == .completed)
        #expect(e.state.summary?.gradedCount == 2)
    }

    @Test func emptyPoolFinishesImmediately() {
        let config = SessionConfig(deckID: FretboardNotesDeck.deckID, options: .fretboard(FretboardOptions(strings: [])))
        let (e, _) = makeEngine(config: config)
        let effects = e.start()
        #expect(e.state.isFinished)
        #expect(effects.compactMap(\.session).last?.status == .abandoned)
    }

    @Test func sameSeedGivesSameSession() {
        func run() -> [ItemKey] {
            let (e, clock) = makeEngine(seed: 77)
            _ = e.start()
            var i = 0
            driveUntilFinished(e, clock: clock) { _ in i += 1; return i % 3 != 0 }
            return e.attempts.map(\.itemKey)
        }
        #expect(run() == run())
    }

    @Test func idleAndFinishedIgnoreInputs() {
        let (e, _) = makeEngine()
        e.ok()
        e.promptDidAppear()
        #expect(e.grade(correct: true).isEmpty)
        #expect(e.pause().isEmpty)
        e.resume()
        #expect(e.state == .idle)
    }

    // MARK: F4 — grade lockout

    @Test func gradeWithinLockoutIsIgnored() {
        let (e, clock) = makeEngine()
        _ = e.start()
        e.promptDidAppear()
        clock.advance(by: .seconds(1))
        e.ok()
        clock.advance(by: .milliseconds(100))
        #expect(!e.canGrade)
        let before = e.state
        #expect(e.grade(correct: true).isEmpty)
        #expect(e.state == before)
        #expect(e.attempts.isEmpty)
        clock.advance(by: .milliseconds(149))
        #expect(!e.canGrade)
        clock.advance(by: .milliseconds(1))
        #expect(e.canGrade, "exactly 250 ms is allowed")
        #expect(e.grade(correct: true).count == 2)
    }

    @Test func pauseDuringRevealDoesNotShortenLockout() {
        let (e, clock) = makeEngine()
        _ = e.start()
        e.promptDidAppear()
        clock.advance(by: .seconds(1))
        e.ok()
        clock.advance(by: .milliseconds(100))
        #expect(e.pause().isEmpty, "pausing a revealed card stores nothing")
        clock.advance(by: .seconds(10))
        e.resume()
        #expect(e.state.isRevealed)
        #expect(!e.canGrade)
        #expect(e.grade(correct: true).isEmpty)
        clock.advance(by: .milliseconds(150))
        #expect(e.canGrade)
        let a = e.grade(correct: true).first?.attempt
        #expect(a?.gradeMs == 250, "paused time excluded from gradeMs")
    }

    @Test func canGradeFalseOutsideReveal() {
        let (e, clock) = makeEngine()
        #expect(!e.canGrade)
        _ = e.start()
        clock.advance(by: .seconds(5))
        #expect(!e.canGrade)
    }

    // MARK: Interruptions (§9.1)

    @Test func pauseWhilePromptingStoresInterruptedAttemptAndReshowsWithFreshTimer() {
        let (e, clock) = makeEngine()
        _ = e.start()
        guard case let .prompting(first) = e.state else { Issue.record("expected prompting"); return }
        e.promptDidAppear()
        clock.advance(by: .milliseconds(700))
        let effects = e.pause()
        #expect(effects.count == 1)
        let interrupted = effects[0].attempt!
        #expect(interrupted.wasInterrupted && !interrupted.correct && !interrupted.isCounted)
        #expect(interrupted.responseMs == 700)

        clock.advance(by: .seconds(30))
        e.resume()
        guard case let .prompting(again) = e.state else { Issue.record("expected prompting"); return }
        #expect(again.card == first.card)
        #expect(again.presentationID != first.presentationID)

        e.promptDidAppear()
        clock.advance(by: .milliseconds(900))
        e.ok()
        clock.advance(by: .milliseconds(300))
        let graded = e.grade(correct: true)
        #expect(graded.first?.attempt?.responseMs == 900)
        #expect(graded.first?.attempt?.index == 1)
        #expect(e.stats[first.card.key]?.attempts == 1, "interrupted attempt excluded from stats")
        #expect(e.state.summary == nil)
    }

    @Test func pausedTimeExcludedFromTimedSession() {
        let config = SessionConfig(deckID: FretboardNotesDeck.deckID, options: .fretboard(FretboardOptions()), length: .minutes(1))
        let (e, clock) = makeEngine(config: config)
        _ = e.start()
        _ = e.pause()
        clock.advance(by: .seconds(600))
        #expect(e.activeElapsed == .zero)
        e.resume()
        #expect(e.activeElapsed == .zero)
        #expect(e.progress == 0)
    }

    @Test func timedSessionEndsAfterTheCardGradedPastTheLimit() {
        let config = SessionConfig(deckID: FretboardNotesDeck.deckID, options: .fretboard(FretboardOptions()), length: .minutes(1))
        let (e, clock) = makeEngine(config: config)
        _ = e.start()
        // Each card takes 10 s + 0.3 s → 6 cards = 61.8 s ≥ 60 s.
        var n = 0
        while case .prompting = e.state, n < 100 {
            drive(e, clock: clock, grades: [true], response: .seconds(10))
            n += 1
        }
        #expect(e.state.isFinished)
        #expect(e.countedGraded == 6)
        #expect(e.progress == 1)
    }

    // MARK: Retries (§9.3 #2)

    @Test func wrongCardIsRetriedAfter3To5CardsWithoutUpdatingStatsAgain() {
        for seed in 0..<50 as Range<UInt64> {
            let (e, clock) = makeEngine(seed: seed)
            _ = e.start()
            guard case let .prompting(first) = e.state else { Issue.record("expected prompting"); return }
            drive(e, clock: clock, grades: [false])
            var gap = 0
            while case let .prompting(p) = e.state, gap < 10 {
                gap += 1
                if p.card.key == first.card.key {
                    #expect(p.isRetry)
                    break
                }
                drive(e, clock: clock, grades: [true])
            }
            #expect((4...6).contains(gap), "seed \(seed): retry shown as card \(gap) after the miss")
            let statsBefore = e.stats[first.card.key]
            let effects = drive(e, clock: clock, grades: [true])
            #expect(effects.first?.attempt?.isRetry == true)
            #expect(effects.compactMap(\.itemStats).isEmpty, "retries never update stats")
            #expect(e.stats[first.card.key] == statsBefore)
        }
    }

    @Test func retriesDoNotCountTowardLength() {
        let config = SessionConfig(deckID: FretboardNotesDeck.deckID, options: .fretboard(FretboardOptions()), length: .cards(10))
        let (e, clock) = makeEngine(config: config, seed: 3)
        _ = e.start()
        var i = 0
        driveUntilFinished(e, clock: clock) { _ in i += 1; return i > 3 }
        #expect(e.countedGraded == 10)
        #expect(e.attempts.filter(\.isRetry).count == 3)
        #expect(e.attempts.count == 13)
    }

    @Test func retriesOffMeansNoRetries() {
        let config = SessionConfig(deckID: FretboardNotesDeck.deckID, options: .fretboard(FretboardOptions()), retryWrongCards: false)
        let (e, clock) = makeEngine(config: config)
        _ = e.start()
        driveUntilFinished(e, clock: clock) { _ in false }
        #expect(!e.attempts.contains { $0.isRetry })
    }

    @Test func atMostOneRetryPerCardPerSession() {
        let pool = Array(fretboardCards().prefix(4))
        let deck = FixedDeck(pool: pool)
        let config = SessionConfig(deckID: deck.id, options: deck.defaultOptions, length: .cards(30))
        let (e, clock) = makeEngine(deck: deck, config: config, seed: 8)
        _ = e.start()
        driveUntilFinished(e, clock: clock) { _ in false }
        let retriesPerKey = Dictionary(grouping: e.attempts.filter(\.isRetry), by: \.itemKey).mapValues(\.count)
        #expect(retriesPerKey.values.allSatisfy { $0 == 1 })
        #expect(e.countedGraded == 30)
    }

    // MARK: F3 — retry/fallback interplay

    /// Review trace: 4-card pool, K = 3, retries on; cards 1 and 2 wrong.
    @Test(arguments: 0..<200 as Range<UInt64>)
    func noCountedPickWhileItsRetryIsPending(seed: UInt64) {
        let pool = Array(fretboardCards().prefix(4))
        let deck = FixedDeck(pool: pool)
        let config = SessionConfig(deckID: deck.id, options: deck.defaultOptions, length: .cards(12))
        let (e, clock) = makeEngine(deck: deck, config: config, seed: seed)
        _ = e.start()
        var pending = Set<ItemKey>()
        var countedShows: [ItemKey: Int] = [:]
        var n = 0
        while case let .prompting(p) = e.state, n < 200 {
            n += 1
            if p.isRetry {
                #expect(pending.remove(p.card.key) != nil, "retry shown that was not pending")
            } else {
                #expect(!pending.contains(p.card.key), "seed \(seed): \(p.card.key) shown as counted pick while its retry is pending")
                countedShows[p.card.key, default: 0] += 1
            }
            let wrong = !p.isRetry && n <= 2
            let effects = drive(e, clock: clock, grades: [!wrong])
            if wrong { pending.insert(p.card.key) }
            _ = effects
        }
        #expect(e.state.isFinished)
        for (key, shows) in countedShows {
            #expect(e.stats[key]?.attempts == shows, "stats updated exactly once per counted show")
        }
    }

    @Test func onePoolCardWithRetriesStillReachesLength() {
        let pool = Array(fretboardCards().prefix(1))
        let deck = FixedDeck(pool: pool)
        let config = SessionConfig(deckID: deck.id, options: deck.defaultOptions, length: .cards(5))
        let (e, clock) = makeEngine(deck: deck, config: config)
        _ = e.start()
        driveUntilFinished(e, clock: clock, cap: 50) { _ in false }
        #expect(e.state.isFinished)
        #expect(e.countedGraded == 5)
    }

    @Test func gatedVocabSessionNeverShowsGatedCards() {
        let deck = vocabDeck(count: 30)
        let config = SessionConfig(deckID: deck.id, options: .vocab(VocabOptions(newPerSession: 2)), length: .cards(20))
        for seed in 0..<30 as Range<UInt64> {
            let (e, clock) = makeEngine(deck: deck, config: config, seed: seed)
            _ = e.start()
            var i = 0
            driveUntilFinished(e, clock: clock) { _ in i += 1; return i % 2 == 0 }
            let allowed = Set(deck.cards(options: config.options).prefix(6).map(\.key)) // fill rule: ≥ 6 eligible
            #expect(e.attempts.allSatisfy { allowed.contains($0.itemKey) })
        }
    }

    @Test func priorEwmaIsSnapshotAtSessionStart() {
        let pool = fretboardCards()
        let key = pool[0].key
        let stats = [key: seenStats(key, ewma: 2_500)]
        let deck = FixedDeck(pool: [pool[0], pool[1]])
        let (e, clock) = makeEngine(deck: deck, config: SessionConfig(deckID: deck.id, options: deck.defaultOptions, length: .cards(6)), stats: stats)
        _ = e.start()
        driveUntilFinished(e, clock: clock) { p in
            if p.card.key == key { #expect(p.priorEwmaMs == 2_500) } else { #expect(p.priorEwmaMs == nil) }
            return true
        }
    }
}

/// A deck serving a fixed pool with no pattern penalties.
struct FixedDeck: Deck {
    let pool: [Card]
    let id: DeckID = FretboardNotesDeck.deckID
    let title = "Fixed", subtitle = ""
    let subject = Subject.music
    var defaultOptions: DeckOptions { .fretboard(FretboardOptions()) }
    func cards(options: DeckOptions) -> [Card] { pool }
    func patternPenalty(candidate: Card, recent: ArraySlice<Card>) -> Double { 1 }
}
