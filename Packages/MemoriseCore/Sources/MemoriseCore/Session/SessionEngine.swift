import Foundation

/// A card currently on screen.
public struct PresentedCard: Sendable, Hashable {
    public let card: Card
    public let isRetry: Bool
    /// Item time EWMA at session start (for coloring the response time).
    public let priorEwmaMs: Double?
    /// Unique per presentation; re-shown cards (after a pause) get a new value.
    public let presentationID: Int
}

/// Observable state of a session.
public enum SessionState: Sendable, Hashable {
    case idle
    case prompting(PresentedCard)
    case revealed(PresentedCard, responseMs: Int)
    /// `responseMs` is non-nil when paused from the reveal state.
    case paused(PresentedCard, responseMs: Int?)
    case finished(SessionSummary)

    public var presented: PresentedCard? {
        switch self {
        case let .prompting(p), let .revealed(p, _), let .paused(p, _): p
        case .idle, .finished: nil
        }
    }
}

/// Persistence side effects emitted by the engine, to be applied in order.
public enum SessionEffect: Sendable {
    case upsertSession(SessionRecord)
    case saveAttempt(Attempt)
    case saveStats(ItemStats)
}

/// Pure session state machine (§9.3). Not thread-safe: drive it from one actor.
///
/// The engine is synchronous; every mutating call returns the `SessionEffect`s that must be
/// persisted (use `SessionRecorder` to apply them sequentially).
public final class SessionEngine {
    public let deck: any Deck
    public let config: SessionConfig
    public let constants: SchedulerConstants
    public private(set) var state: SessionState = .idle
    public private(set) var record: SessionRecord
    /// Current item stats (updated live).
    public private(set) var stats: [ItemKey: ItemStats]
    /// Every stored attempt, in order.
    public private(set) var attempts: [Attempt] = []
    /// Counted graded cards so far.
    public private(set) var countedGraded = 0

    private let scheduler: Scheduler
    private let clock: any MonotonicClock
    private let wallClock: @Sendable () -> Date
    private var rng: SplitMix64
    private let priorEwma: [ItemKey: Double]
    private let previous: SessionBaseline?

    private var history: [Card] = []
    private var shownCards: [ItemKey: Card] = [:]
    private var pendingRetries: [(card: Card, dueAt: Int)] = []
    private var retriedKeys = Set<ItemKey>()
    private var presentationCounter = 0

    // Timing (monotonic).
    private var sessionStart: Duration = .zero
    private var pausedTotal: Duration = .zero
    private var pausedAt: Duration?
    private var promptShownAt: Duration?
    private var cardSelectedAt: Duration = .zero
    private var revealedAt: Duration = .zero
    /// Whether the current reveal's response time feeds the time EWMA (set by `ok`).
    private var revealCountsTime = true
    private var shownAtWall = Date.distantPast

    public init(
        deck: any Deck,
        config: SessionConfig,
        stats: [ItemKey: ItemStats],
        previous: SessionBaseline? = nil,
        clock: any MonotonicClock = ContinuousMonotonicClock(),
        rng: SplitMix64 = SplitMix64(),
        sessionID: UUID = UUID(),
        wallClock: @escaping @Sendable () -> Date = { Date() },
        constants: SchedulerConstants = .standard
    ) {
        self.deck = deck
        self.config = config
        self.constants = constants
        self.clock = clock
        self.wallClock = wallClock
        self.rng = rng
        self.previous = previous
        self.stats = stats

        let pool = deck.cards(options: config.options)
        let newPerSession = deck.newPerSession(options: config.options) ?? .max
        self.scheduler = Scheduler(
            deck: deck,
            pool: pool,
            focus: config.focus,
            eligibleNew: IntroductionPolicy.eligibleNewKeys(
                pool: pool, stats: stats, deck: deck, newPerSession: newPerSession, constants: constants
            ),
            constants: constants
        )
        var prior: [ItemKey: Double] = [:]
        for card in pool { if let e = stats[card.key]?.ewmaResponseMs { prior[card.key] = e } }
        self.priorEwma = prior
        self.record = SessionRecord(id: sessionID, deckID: deck.id, startedAt: wallClock(), status: .inProgress, config: config)
    }

    /// Number of cards available under the configured options.
    public var poolSize: Int { scheduler.pool.count }

    /// Active (non-paused) elapsed time since `start()`.
    public var activeElapsed: Duration {
        let end = pausedAt ?? clock.now()
        return end - sessionStart - pausedTotal
    }

    /// Progress toward the configured length in 0…1.
    public var progress: Double {
        switch config.length {
        case let .cards(n): n > 0 ? min(1, Double(countedGraded) / Double(n)) : 1
        case let .minutes(m): m > 0 ? min(1, activeElapsed / .seconds(m * 60)) : 1
        }
    }

    /// Elapsed time on the current prompt (for an optional on-screen timer).
    public var currentPromptElapsed: Duration? {
        guard case .prompting = state, let start = promptShownAt else { return nil }
        return clock.now() - start
    }

    // MARK: Transitions

    /// idle → prompting(first card). Finishes immediately when the pool is empty.
    public func start() -> [SessionEffect] {
        guard case .idle = state else { return [] }
        sessionStart = clock.now()
        var effects: [SessionEffect] = [.upsertSession(record)]
        if !presentNext() { effects += finish() }
        return effects
    }

    /// Call when the prompt is fully visible; starts the response timer.
    public func promptDidAppear() {
        guard case .prompting = state, promptShownAt == nil else { return }
        promptShownAt = clock.now()
    }

    /// prompting → revealed. Records the response time.
    ///
    /// `countsTime` describes how *this* card was answered (R4-4), not the session's configured
    /// mode: pass `false` for typed/choice reveals and for a microphone timeout reveal.
    public func ok(countsTime: Bool = true) {
        guard case let .prompting(p) = state else { return }
        revealCountsTime = countsTime
        let now = clock.now()
        let ms = (now - (promptShownAt ?? cardSelectedAt)).wholeMilliseconds
        revealedAt = now
        state = .revealed(p, responseMs: ms)
    }

    /// Time left before a grade is accepted; `.zero` unless revealed. Paused time is excluded.
    public var gradeLockoutRemaining: Duration {
        guard case .revealed = state else { return .zero }
        return max(.zero, .milliseconds(constants.gradeLockoutMs) - (clock.now() - revealedAt))
    }

    /// True when revealed and the grade lockout (`gradeLockoutMs`) has elapsed.
    public var canGrade: Bool {
        guard case .revealed = state else { return false }
        return gradeLockoutRemaining == .zero
    }

    /// revealed → next card / finished. Persists attempt + stats.
    /// Ignored (no effects, no state change) while `canGrade` is false.
    public func grade(correct: Bool) -> [SessionEffect] {
        guard canGrade else { return [] }
        return gradeRevealed(correct: correct, gradeMs: (clock.now() - revealedAt).wholeMilliseconds, countsTime: revealCountsTime)
    }

    private func gradeRevealed(correct: Bool, gradeMs: Int, countsTime: Bool) -> [SessionEffect] {
        guard case let .revealed(p, responseMs) = state else { return [] }
        let now = wallClock()
        let attempt = makeAttempt(p, responseMs: responseMs, gradeMs: gradeMs, correct: correct, interrupted: false)
        var effects: [SessionEffect] = [.saveAttempt(attempt)]

        if !p.isRetry {
            countedGraded += 1
            let key = p.card.key
            let updated = StatsUpdater.apply(
                responseMs: responseMs, correct: correct, at: now,
                to: stats[key] ?? .empty(key: key, deck: deck.id), constants: constants,
                updateTime: countsTime
            )
            stats[key] = updated
            effects.append(.saveStats(updated))

            if !correct, config.retryWrongCards, retriedKeys.insert(key).inserted {
                let delay = Int.random(in: constants.retryDelay, using: &rng)
                pendingRetries.append((p.card, history.count + delay))
            }
        }

        if isLengthReached || !presentNext() { effects += finish() }
        return effects
    }

    /// Current time on the engine's monotonic clock (for mapping external timestamps).
    public var clockNow: Duration { clock.now() }

    /// Automatically evaluated answer (microphone, choice, typed) given at `at` (engine clock).
    ///
    /// Valid only while prompting. Performs `ok` at `at` (`responseMs` from the prompt, ≥ 0) and
    /// grades immediately with `gradeMs = 0`, bypassing the human double-tap lockout.
    /// `countsTime: false` keeps the response time out of the time EWMA. An onset before the prompt
    /// is recorded untimed (R6-3).
    public func answerEvaluated(correct: Bool, at: Duration, countsTime: Bool) -> [SessionEffect] {
        guard case let .prompting(p) = state else { return [] }
        let start = promptShownAt ?? cardSelectedAt
        // R6-3: an onset before the prompt is not a real response time; record the answer untimed.
        let timed = countsTime && at >= start
        let ms = (max(at, start) - start).wholeMilliseconds
        revealedAt = clock.now() - .milliseconds(constants.gradeLockoutMs)
        state = .revealed(p, responseMs: ms)
        return gradeRevealed(correct: correct, gradeMs: 0, countsTime: timed)
    }

    /// Microphone answer: a correct note was detected with onset at `onset` (engine clock).
    public func answerDetected(at onset: Duration) -> [SessionEffect] {
        answerEvaluated(correct: true, at: onset, countsTime: true)
    }

    /// Pause / interruption (app backgrounded). A visible prompt is stored as interrupted
    /// and will be re-shown with a fresh timer on `resume()`.
    public func pause() -> [SessionEffect] {
        let now = clock.now()
        switch state {
        case let .prompting(p):
            pausedAt = now
            let ms = (now - (promptShownAt ?? cardSelectedAt)).wholeMilliseconds
            state = .paused(p, responseMs: nil)
            return [.saveAttempt(makeAttempt(p, responseMs: ms, gradeMs: 0, correct: false, interrupted: true))]
        case let .revealed(p, ms):
            pausedAt = now
            state = .paused(p, responseMs: ms)
            return []
        default:
            return []
        }
    }

    /// paused → prompting(same card, new timer) or back to revealed.
    public func resume() {
        guard case let .paused(p, ms) = state else { return }
        let now = clock.now()
        if let at = pausedAt {
            pausedTotal += now - at
            if ms != nil { revealedAt += now - at }
        }
        pausedAt = nil
        if let ms {
            state = .revealed(p, responseMs: ms)
        } else {
            show(p.card, isRetry: p.isRetry, at: now, resumed: true)
        }
    }

    /// Ends the session early; completed if anything was graded, else abandoned.
    public func quit() -> [SessionEffect] {
        if case .finished = state { return [] }
        return finish()
    }

    // MARK: Internals

    private var isLengthReached: Bool {
        switch config.length {
        case let .cards(n): countedGraded >= n
        case let .minutes(m): activeElapsed >= .seconds(m * 60)
        }
    }

    /// Presents the next card. Returns false when nothing can be shown.
    private func presentNext() -> Bool {
        let now = clock.now()
        if let i = dueRetryIndex() {
            let retry = pendingRetries.remove(at: i)
            show(retry.card, isRetry: true, at: now)
            return true
        }
        let excluded = Set(pendingRetries.map(\.card.key))
        let wallNow = wallClock()
        // 1. Regular weighted pick within cooldown rules.
        if let picked = scheduler.nextCard(history: history, stats: stats, excluded: excluded, now: wallNow, allowFallback: false, rng: &rng) {
            show(deck.present(picked, options: config.options, using: &rng), isRetry: false, at: now)
            return true
        }
        // 2. Prefer an early pending retry (not back-to-back) over a cooldown-breaking pick.
        if let i = earliestRetryIndex(excludingKey: history.last?.key) {
            show(pendingRetries.remove(at: i).card, isRetry: true, at: now)
            return true
        }
        // 3. Uniform fallback over the allowed set.
        if let picked = scheduler.nextCard(history: history, stats: stats, excluded: excluded, now: wallNow, allowFallback: true, rng: &rng) {
            show(deck.present(picked, options: config.options, using: &rng), isRetry: false, at: now)
            return true
        }
        // 4. Flush any remaining retry, even back-to-back, rather than ending the session.
        if let i = earliestRetryIndex(excludingKey: nil) {
            show(pendingRetries.remove(at: i).card, isRetry: true, at: now)
            return true
        }
        return false
    }

    /// Pending retry with the smallest `dueAt` whose key differs from `key`.
    private func earliestRetryIndex(excludingKey key: ItemKey?) -> Int? {
        var best: Int?
        for (i, r) in pendingRetries.enumerated() where r.card.key != key {
            if best == nil || r.dueAt < pendingRetries[best!].dueAt { best = i }
        }
        return best
    }

    /// First retry that is due and outside the cooldown window (delayed otherwise).
    private func dueRetryIndex() -> Int? {
        guard !pendingRetries.isEmpty else { return nil }
        let blocked = Set(history.suffix(scheduler.cooldown).map(\.key))
        var best: Int?
        for (i, r) in pendingRetries.enumerated() where r.dueAt <= history.count && !blocked.contains(r.card.key) {
            if best == nil || r.dueAt < pendingRetries[best!].dueAt { best = i }
        }
        return best
    }

    private func show(_ card: Card, isRetry: Bool, at now: Duration, resumed: Bool = false) {
        // A re-shown (resumed) card is not appended twice to history.
        if !resumed { history.append(card) }
        shownCards[card.key] = card
        presentationCounter += 1
        promptShownAt = nil
        cardSelectedAt = now
        shownAtWall = wallClock()
        state = .prompting(PresentedCard(card: card, isRetry: isRetry, priorEwmaMs: priorEwma[card.key], presentationID: presentationCounter))
    }

    private func makeAttempt(_ p: PresentedCard, responseMs: Int, gradeMs: Int, correct: Bool, interrupted: Bool) -> Attempt {
        let a = Attempt(
            id: UUID(), sessionID: record.id, itemKey: p.card.key, deckID: deck.id, index: attempts.count,
            shownAt: shownAtWall, responseMs: responseMs, gradeMs: gradeMs, correct: correct,
            isRetry: p.isRetry, wasInterrupted: interrupted
        )
        attempts.append(a)
        return a
    }

    private func finish() -> [SessionEffect] {
        if let at = pausedAt { pausedTotal += clock.now() - at; pausedAt = nil }
        record.endedAt = wallClock()
        record.status = countedGraded > 0 ? .completed : .abandoned
        let shown = shownCards
        state = .finished(SessionSummary.build(
            session: record, attempts: attempts, cardLookup: { shown[$0] },
            priorEwma: priorEwma, previous: previous, constants: constants
        ))
        return [.upsertSession(record)]
    }
}
