import Foundation
import MemoriseCore
import Observation
import os

/// An automatically checked answer (typed / choice) waiting on the reveal for Next.
struct AutoAnswer: Hashable {
    let verdict: AnswerVerdict
    /// What the user typed (typed mode).
    let input: String?
    /// The tapped option (choice mode).
    let chosen: AnswerChoice?
    /// The expected answer closest to the input.
    let expected: String
    let exactRequired: Bool
    /// "I was right" / "I was wrong".
    var override: Bool?

    /// The grade Next will store.
    var correct: Bool { override ?? verdict.isCorrect(exactRequired: exactRequired) }
}

/// Microphone answer feedback shown over the card (R7-F3).
enum MicFeedback: Hashable {
    /// The card accepted the note; the next card follows after `SessionViewModel.micCorrectDelay`.
    case correct
    /// A stable note the card doesn't accept; still listening.
    case tryAgain(heard: String)
    /// The third wrong note: the answer is revealed and graded wrong.
    case notQuite

    var text: String {
        switch self {
        case .correct: "Correct"
        case let .tryAgain(heard): "Try again · heard \(heard)"
        case .notQuite: "Not quite: here's the answer"
        }
    }

    /// What spoken feedback says.
    var spoken: String {
        switch self {
        case .correct: "Correct"
        case .tryAgain: "Try again"
        case .notQuite: "Not quite"
        }
    }

    var isPositive: Bool { self == .correct }
}

/// Drives a `SessionEngine` from the UI and persists its effects in order.
@MainActor @Observable
final class SessionViewModel {
    let deck: any Deck
    let config: SessionConfig
    private(set) var state: SessionState = .idle
    private(set) var loadError: String?
    /// Effects that failed to persist this session.
    private(set) var saveFailures = 0
    /// Set once when a vocab card is revealed and no Korean voice is installed.
    var showVoiceHint = false
    /// Microphone controller when the session answers by playing (and permission is granted).
    private(set) var mic: MicAnswerController?
    /// Why mic mode fell back to touch, if it did.
    private(set) var micFallbackReason: String?
    /// Choice mode: options for the current prompt.
    private(set) var choices: [AnswerChoice]?
    /// Typed mode: what the current prompt is checked against.
    private(set) var typedSpec: TypedAnswerSpec?
    /// Set when a typed/choice answer has been checked (shown on the reveal).
    private(set) var autoAnswer: AutoAnswer?
    /// M5 K4: the entry whose "My snippet" sheet is open (the session is paused meanwhile).
    var snippetTarget: SnippetEditTarget?
    /// Set when "End session" erased the session (R7-F2); the view dismisses without a summary.
    private(set) var discarded = false
    /// Microphone answer banner (R7-F3); `micFeedbackID` changes on every new event.
    private(set) var micFeedback: MicFeedback?
    private(set) var micFeedbackID = 0

    @ObservationIgnored let ui: any DeckUI
    @ObservationIgnored private let env: AppEnvironment
    @ObservationIgnored private var engine: SessionEngine?
    @ObservationIgnored private var recorder: SessionRecorder?
    @ObservationIgnored private var micTimeoutTask: Task<Void, Never>?
    @ObservationIgnored private var preparedPresentation: Int?
    @ObservationIgnored private var choiceRNG = SplitMix64()
    // Microphone feedback (R7-F3).
    @ObservationIgnored private var wrongNoteCount = 0
    @ObservationIgnored private var lastWrongNote: (midi: Int, at: ContinuousClock.Instant)?
    /// The pending "Correct" → grade step; non-nil while a correct note is being confirmed.
    @ObservationIgnored private var micAnswerTask: Task<Void, Never>?
    @ObservationIgnored private var micFeedbackClearTask: Task<Void, Never>?
    @ObservationIgnored private var micAutoGradeTask: Task<Void, Never>?
    /// Signpost intervals that end in the view (PLAN_R11 PA3): reveal → answer visible, grade → next prompt visible.
    @ObservationIgnored private var revealVisibleInterval: OSSignpostIntervalState?
    @ObservationIgnored private var nextPromptInterval: OSSignpostIntervalState?
    /// The current reveal came from the third wrong note: any grade is stored as wrong.
    @ObservationIgnored private var micForcedWrong = false

    /// Pause between "Correct" and the next card. The grade uses the note's onset, so this
    /// doesn't inflate `responseMs`.
    static let micCorrectDelay: Duration = .milliseconds(900)
    /// Wrong notes on one card before the answer is revealed and graded wrong.
    static let micMaxWrongNotes = 3
    /// The revealed answer after the last wrong note is graded wrong after this delay.
    static let micAutoGradeDelay: Duration = .milliseconds(1500)
    /// How long "Try again" stays up.
    static let micTryAgainVisible: Duration = .milliseconds(1200)

    init(env: AppEnvironment, deck: any Deck, config: SessionConfig) {
        self.env = env
        self.deck = deck
        self.config = config
        self.ui = env.deckUI(for: deck)
    }

    // MARK: Derived

    var countedGraded: Int { engine?.countedGraded ?? 0 }
    var progress: Double { engine?.progress ?? 0 }

    /// "7 / 20" for card sessions.
    var progressText: String? {
        guard case let .cards(n) = config.length else { return nil }
        return "\(min(countedGraded + 1, n)) / \(n)"
    }

    /// Remaining seconds for timed sessions (polled by a `TimelineView`).
    var remainingSeconds: TimeInterval? {
        guard case let .minutes(m) = config.length, let engine else { return nil }
        return max(0, Double(m * 60) - engine.activeElapsed.timeInterval)
    }

    /// Elapsed seconds on the current prompt (polled).
    var promptElapsedSeconds: Double? {
        engine?.currentPromptElapsed?.timeInterval
    }

    /// Rendering context for the current presentation.
    func context(presentationID: Int) -> DeckUIContext {
        DeckUIContext(
            env: env, deck: deck, options: config.options, presentationID: presentationID,
            promptDidAppear: { [weak self] in self?.promptDidAppear() },
            requestVoiceHint: { [weak self] in self?.showVoiceHint = true },
            pauseSession: { [weak self] in self?.pause() },
            resumeSession: { [weak self] in self?.resume() },
            editSnippet: { [weak self] entry in self?.editSnippet(entry) }
        )
    }

    /// Whether the prompt view starts the timer itself (e.g. ear training).
    func managesPromptTiming(_ card: Card) -> Bool { ui.managesPromptTiming(card) }

    // MARK: Lifecycle

    func start() async {
        guard engine == nil else { return }
        // The previous session may still be writing: wait for it before reading stats, baseline and history.
        await env.pendingFlush?.value
        guard engine == nil else { return }
        do {
            async let stats = env.store.stats(for: deck.id)
            async let previous = env.store.baselineOfLastCompletedSession(for: deck.id)
            async let history = env.store.deckHistory(for: deck.id)
            let engine = SessionEngine(
                deck: deck, config: config, stats: try await stats, previous: try await previous,
                history: try await history
            )
            let recorder = SessionRecorder(store: env.store) { [weak self] error in
                AppEnvironment.log.error("Persist failed: \(error.localizedDescription, privacy: .public)")
                Task { @MainActor [weak self] in self?.saveFailures += 1 }
            }
            self.engine = engine
            self.recorder = recorder
            env.haptics.isEnabled = env.settings.hapticsEnabled
            env.haptics.prepare()
            await startMicIfNeeded()
            apply(engine.start())
            // Load the Korean voice and the audio session once the first prompt is up, not on the first reveal.
            if deck.subject == .korean, env.speech.hasKoreanVoice {
                Task { [env] in
                    await Task.yield()
                    env.speech.prewarm()
                }
            }
        } catch {
            loadError = error.localizedDescription
        }
    }

    func promptDidAppear() {
        engine?.promptDidAppear()
        armMicTimeout()
    }

    func ok() {
        reveal(countsTime: true)
    }

    /// Manual reveal. A touch reveal (including the touch fallback for cards without choices or a
    /// typed spec) counts its time; a microphone timeout reveal doesn't (R4-4).
    private func reveal(countsTime: Bool) {
        guard let engine, case .prompting = engine.state, micAnswerTask == nil else { return }
        // Typed / choice prompts reveal through `submitTyped` / `choose` / `giveUp`.
        guard choices == nil, typedSpec == nil else { return }
        beginRevealIntervals()
        Perf.interval("session.reveal") {
            engine.ok(countsTime: countsTime)
            env.haptics.ok()
            syncState()
        }
        if case let .revealed(p, _) = state { ui.onReveal(p.card, ctx: context(presentationID: p.presentationID)) }
    }

    /// Time left in the grade lockout (`.zero` when grading is allowed or not revealed).
    var gradeLockoutRemaining: Duration { engine?.gradeLockoutRemaining ?? .zero }

    /// Applies a grade. Returns false when rejected (not revealed, or still in the lockout).
    /// `haptic: false` when the reveal already played the verdict haptic (typed/choice, R5-6b).
    @discardableResult
    func grade(correct: Bool, haptic: Bool = true) -> Bool {
        guard let engine, engine.canGrade else { return false }
        // R7-F3: a reveal after the last wrong note is always graded wrong.
        let correct = correct && !micForcedWrong
        micAutoGradeTask?.cancel()
        micForcedWrong = false
        env.speech.stop()
        if haptic { env.haptics.grade(correct: correct) }
        if let old = nextPromptInterval { Perf.end("session.nextPrompt", old) }
        nextPromptInterval = Perf.begin("session.nextPrompt")
        apply(engine.grade(correct: correct))
        return true
    }

    private func beginRevealIntervals() {
        if let old = revealVisibleInterval { Perf.end("session.revealVisible", old) }
        revealVisibleInterval = Perf.begin("session.revealVisible")
    }

    /// The revealed answer is on screen (called from the view).
    func revealDidAppear() {
        guard let state = revealVisibleInterval else { return }
        revealVisibleInterval = nil
        Perf.end("session.revealVisible", state)
    }

    /// The next prompt is on screen (called from the view).
    func promptViewDidAppear() {
        guard let state = nextPromptInterval else { return }
        nextPromptInterval = nil
        Perf.end("session.nextPrompt", state)
    }

    func pause() {
        guard let engine else { return }
        // A pending "Correct" is dropped: the card is re-shown unanswered on resume.
        cancelMicFeedback()
        apply(engine.pause())
    }

    func resume() {
        guard let engine else { return }
        engine.resume()
        syncState()
    }

    /// Opens the snippet sheet; the session pauses (same path as ✕) so grade time isn't inflated.
    func editSnippet(_ entry: VocabEntry) {
        pause()
        snippetTarget = SnippetEditTarget(entry: entry)
    }

    /// Sheet dismissed: resume where we left off.
    func snippetSheetDismissed() {
        snippetTarget = nil
        resume()
    }

    /// "End session" (R7-F2): before the length is reached the session is discarded and leaves no
    /// trace (no record, no attempts, stats restored). A reached length finishes normally.
    func quit() {
        guard let engine else { return }
        env.speech.stop()
        if case .finished = engine.state { return }
        if engine.isLengthReached {
            apply(engine.quit())
        } else {
            discarded = true
            apply(engine.discard())
        }
    }

    func speak(_ text: String) { env.speech.speak(text, rate: env.settings.speechRate) }

    // MARK: Typed / choice answers

    /// Whether the session shows the persistent answer text field.
    var usesTextField: Bool { config.inputMode == .typed }

    /// The answer mode in effect for the current card (cards without choices/typed spec fall back to touch).
    var activeMode: InputMode {
        if choices != nil { return .choice }
        if typedSpec != nil { return .typed }
        if mic != nil { return .microphone }
        return .touch
    }

    /// Choice mode: the user tapped an option. Records the time, reveals with the verdict.
    func choose(_ choice: AnswerChoice) {
        guard let engine, case .prompting = engine.state, let choices, choices.contains(choice) else { return }
        let expected = choices.first(where: \.isCorrect)?.label ?? ""
        reveal(engine, AutoAnswer(verdict: choice.isCorrect ? .exact : .wrong, input: nil, chosen: choice,
                                  expected: expected, exactRequired: true))
    }

    /// Typed mode: Return pressed. Records the time, reveals with the verdict.
    func submitTyped(_ text: String) {
        guard let engine, case .prompting = engine.state, let typedSpec else { return }
        let input = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { return }
        let result = AnswerMatcher.match(input: input, spec: typedSpec)
        reveal(engine, AutoAnswer(verdict: result.verdict, input: input, chosen: nil,
                                  expected: result.closest, exactRequired: typedSpec.exactRequired))
    }

    /// Typed mode: "Don't know" — reveal as wrong.
    func giveUp() {
        guard let engine, case .prompting = engine.state, let typedSpec else { return }
        reveal(engine, AutoAnswer(verdict: .wrong, input: "", chosen: nil,
                                  expected: typedSpec.expected.first ?? "", exactRequired: typedSpec.exactRequired))
    }

    /// "I was right" / "I was wrong" on a checked answer.
    func overrideAutoAnswer(correct: Bool) {
        autoAnswer?.override = correct
    }

    /// Next on a checked answer: stores the verdict (or the override).
    @discardableResult
    func gradeAutoAnswer() -> Bool {
        guard let autoAnswer else { return false }
        return grade(correct: autoAnswer.correct, haptic: false)
    }

    private func reveal(_ engine: SessionEngine, _ answer: AutoAnswer) {
        // Per-answer mode: typed and choice reveals never feed the time EWMA.
        beginRevealIntervals()
        Perf.interval("session.reveal") {
            engine.ok(countsTime: activeMode.countsTime)
            autoAnswer = answer
            env.haptics.grade(correct: answer.correct)
            syncState()
        }
        if case let .revealed(p, _) = state { ui.onReveal(p.card, ctx: context(presentationID: p.presentationID)) }
    }

    /// Computes choices / typed spec once per presentation.
    private func prepare(_ p: PresentedCard) {
        guard preparedPresentation != p.presentationID else { return }
        preparedPresentation = p.presentationID
        autoAnswer = nil
        wrongNoteCount = 0
        lastWrongNote = nil
        micForcedWrong = false
        choices = config.inputMode == .choice ? ui.choices(for: p.card, options: config.options, using: &choiceRNG) : nil
        typedSpec = config.inputMode == .typed ? ui.typedAnswer(for: p.card) : nil
    }

    // MARK: Microphone

    private func startMicIfNeeded() async {
        guard config.inputMode == .microphone, ui.supportsMicAnswer else { return }
        guard await MicAnswerController.requestPermission() else {
            micFallbackReason = "Microphone access is off — answering by touch."
            return
        }
        let mic = MicAnswerController(audio: env.audio)
        mic.onStableNote = { [weak self] midi, onset in self?.micHeard(midi: midi, onsetHostSeconds: onset) ?? false }
        mic.onWrongNote = { [weak self] midi in self?.micWrongNote(midi: midi) }
        do {
            try mic.start()
            self.mic = mic
        } catch {
            AppEnvironment.log.error("Mic start failed: \(error.localizedDescription, privacy: .public)")
            micFallbackReason = "The microphone couldn't start — answering by touch."
        }
    }

    /// A stable note was heard. Returns true when it answered the card.
    ///
    /// R7-F3: a correct note shows "Correct", then grades after `micCorrectDelay` using the note's
    /// onset. After any wrong note on this card it still says "Correct" and moves on, but stores
    /// the card as wrong (owner D1), so it comes back and the stats stay honest.
    private func micHeard(midi: Int, onsetHostSeconds: Double) -> Bool {
        guard let engine, case let .prompting(p) = engine.state, micAnswerTask == nil else { return false }
        guard ui.micAccepts(p.card, midi: midi) else { return false }
        // Both clocks are monotonic; map the onset onto the engine clock (error < 1 ms while awake).
        let ago = max(0, MicAnswerController.hostNowSeconds - onsetHostSeconds)
        let onset = engine.clockNow - .nanoseconds(Int64(ago * 1e9))
        let firstTry = wrongNoteCount == 0
        mic?.setListening(false)
        micTimeoutTask?.cancel()
        showMicFeedback(.correct, clearAfter: nil)
        env.haptics.grade(correct: true)
        speakMicFeedback(.correct, onFinish: nil)
        let id = p.presentationID
        micAnswerTask = Task { [weak self] in
            try? await Task.sleep(for: Self.micCorrectDelay)
            guard !Task.isCancelled, let self, let engine = self.engine,
                  case let .prompting(cur) = engine.state, cur.presentationID == id else { return }
            self.micAnswerTask = nil
            self.micFeedback = nil
            self.apply(firstTry
                ? engine.answerDetected(at: onset)
                : engine.answerEvaluated(correct: false, at: onset, countsTime: false))
        }
        return true
    }

    /// A stable note the card doesn't accept: "Try again", or on the last allowed wrong note,
    /// reveal the answer and grade it wrong after `micAutoGradeDelay` (a tap grades sooner).
    private func micWrongNote(midi: Int) {
        guard let engine, case let .prompting(p) = engine.state, micAnswerTask == nil else { return }
        // A note still ringing after the mic re-arms (spoken feedback) isn't a new attempt.
        let now = ContinuousClock.now
        if let last = lastWrongNote, last.midi == midi, now - last.at < .seconds(2) {
            lastWrongNote = (midi, now)
            return
        }
        lastWrongNote = (midi, now)
        wrongNoteCount += 1
        env.haptics.grade(correct: false)

        guard wrongNoteCount >= Self.micMaxWrongNotes else {
            let feedback = MicFeedback.tryAgain(heard: MicAnswerController.noteName(midi))
            showMicFeedback(feedback, clearAfter: Self.micTryAgainVisible)
            if env.settings.spokenMicFeedback {
                // Don't let the phone's own voice be heard as a note.
                mic?.setListening(false)
                let id = p.presentationID
                speakMicFeedback(feedback) { [weak self] in
                    guard let self, case let .prompting(cur) = self.state, cur.presentationID == id,
                          self.micAnswerTask == nil else { return }
                    self.mic?.setListening(true)
                }
            }
            return
        }

        micTimeoutTask?.cancel()
        showMicFeedback(.notQuite, clearAfter: Self.micAutoGradeDelay)
        speakMicFeedback(.notQuite, onFinish: nil)
        reveal(countsTime: false)
        guard case let .revealed(revealed, _) = state else { return }
        micForcedWrong = true
        let id = revealed.presentationID
        micAutoGradeTask = Task { [weak self] in
            try? await Task.sleep(for: Self.micAutoGradeDelay)
            guard !Task.isCancelled, let self, case let .revealed(cur, _) = self.state, cur.presentationID == id else { return }
            self.grade(correct: false, haptic: false)
        }
    }

    private func showMicFeedback(_ feedback: MicFeedback, clearAfter delay: Duration?) {
        micFeedback = feedback
        micFeedbackID &+= 1
        micFeedbackClearTask?.cancel()
        guard let delay else { return }
        let id = micFeedbackID
        micFeedbackClearTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self, self.micFeedbackID == id else { return }
            self.micFeedback = nil
        }
    }

    /// Speaks the feedback word in English when enabled; `onFinish` runs either way.
    private func speakMicFeedback(_ feedback: MicFeedback, onFinish: (@MainActor () -> Void)?) {
        guard env.settings.spokenMicFeedback else {
            onFinish?()
            return
        }
        env.speech.speakEnglish(feedback.spoken, onFinish: onFinish)
    }

    private func cancelMicFeedback() {
        micAnswerTask?.cancel()
        micAnswerTask = nil
        micAutoGradeTask?.cancel()
        micFeedbackClearTask?.cancel()
        micFeedback = nil
    }

    /// After the timeout, reveal for manual grading (the mic may have missed a correct note).
    private func armMicTimeout() {
        micTimeoutTask?.cancel()
        guard mic != nil, case let .prompting(p) = state else { return }
        let id = p.presentationID
        let seconds = SessionConfig.nearestMicTimeoutPreset(config.micTimeoutSeconds)
        micTimeoutTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled, let self, case let .prompting(cur) = self.state, cur.presentationID == id else { return }
            // responseMs ≈ the timeout here: keep it out of the time stats.
            self.reveal(countsTime: false)
        }
    }

    func stopMic() {
        micTimeoutTask?.cancel()
        cancelMicFeedback()
        mic?.stop()
        mic = nil
    }

    // MARK: Internals

    private func syncState() {
        guard let engine else { return }
        state = engine.state
        if case let .prompting(p) = state { prepare(p) }
        // Listen only while a prompt is visible (not during reveal / pause / playback).
        if case let .prompting(p) = state {
            if let mic {
                // Spoken feedback ("Correct") may still be playing: the mic must not hear it as the next answer
                // (R7-9f). Wait for the stop without blocking, then arm the mic if this prompt is still showing.
                let id = p.presentationID
                Task { [weak self, weak mic] in
                    await self?.env.speech.stopAndWait()
                    guard let self, let mic, self.mic === mic, case let .prompting(cur) = self.state,
                          cur.presentationID == id else { return }
                    mic.setListening(true)
                }
            }
        } else {
            mic?.setListening(false)
            micTimeoutTask?.cancel()
        }
    }

    private func apply(_ effects: [SessionEffect]) {
        recorder?.record(effects)
        syncState()
        if case .finished = state, let recorder {
            self.recorder = nil
            stopMic()
            let env = env
            // Chained, so closes finish in order and the next `start()` waits for all of them.
            let previous = env.pendingFlush
            env.pendingFlush = Task {
                await previous?.value
                await recorder.close()
                env.dataDidChange()
            }
        }
    }
}

extension Duration {
    /// Seconds as `TimeInterval`.
    var timeInterval: TimeInterval {
        let (s, atto) = components
        return Double(s) + Double(atto) / 1e18
    }
}

/// Identifies the vocab entry being annotated in the snippet sheet.
struct SnippetEditTarget: Identifiable, Hashable {
    let entry: VocabEntry
    var id: String { entry.id }
}
