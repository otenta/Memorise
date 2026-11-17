import Foundation
import MemoriseCore
import Observation

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

    @ObservationIgnored let ui: any DeckUI
    @ObservationIgnored private let env: AppEnvironment
    @ObservationIgnored private var engine: SessionEngine?
    @ObservationIgnored private var recorder: SessionRecorder?
    @ObservationIgnored private var micTimeoutTask: Task<Void, Never>?
    @ObservationIgnored private var preparedPresentation: Int?
    @ObservationIgnored private var choiceRNG = SplitMix64()

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
        do {
            async let stats = env.store.stats(for: deck.id)
            async let previous = env.store.baselineOfLastCompletedSession(for: deck.id)
            let engine = SessionEngine(deck: deck, config: config, stats: try await stats, previous: try await previous)
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
        } catch {
            loadError = error.localizedDescription
        }
    }

    func promptDidAppear() {
        engine?.promptDidAppear()
        armMicTimeout()
    }

    func ok() {
        guard let engine, case .prompting = engine.state else { return }
        // Typed / choice prompts reveal through `submitTyped` / `choose` / `giveUp`.
        guard choices == nil, typedSpec == nil else { return }
        engine.ok()
        env.haptics.ok()
        syncState()
        if case let .revealed(p, _) = state { ui.onReveal(p.card, ctx: context(presentationID: p.presentationID)) }
    }

    /// Time left in the grade lockout (`.zero` when grading is allowed or not revealed).
    var gradeLockoutRemaining: Duration { engine?.gradeLockoutRemaining ?? .zero }

    /// Applies a grade. Returns false when rejected (not revealed, or still in the lockout).
    @discardableResult
    func grade(correct: Bool) -> Bool {
        guard let engine, engine.canGrade else { return false }
        env.speech.stop()
        env.haptics.grade(correct: correct)
        apply(engine.grade(correct: correct))
        return true
    }

    func pause() {
        guard let engine else { return }
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

    func quit() {
        guard let engine else { return }
        env.speech.stop()
        apply(engine.quit())
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
        return grade(correct: autoAnswer.correct)
    }

    private func reveal(_ engine: SessionEngine, _ answer: AutoAnswer) {
        engine.ok()
        autoAnswer = answer
        env.haptics.grade(correct: answer.correct)
        syncState()
        if case let .revealed(p, _) = state { ui.onReveal(p.card, ctx: context(presentationID: p.presentationID)) }
    }

    /// Computes choices / typed spec once per presentation.
    private func prepare(_ p: PresentedCard) {
        guard preparedPresentation != p.presentationID else { return }
        preparedPresentation = p.presentationID
        autoAnswer = nil
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
        do {
            try mic.start()
            self.mic = mic
        } catch {
            AppEnvironment.log.error("Mic start failed: \(error.localizedDescription, privacy: .public)")
            micFallbackReason = "The microphone couldn't start — answering by touch."
        }
    }

    /// A stable note was heard. Returns true when it answered the card.
    private func micHeard(midi: Int, onsetHostSeconds: Double) -> Bool {
        guard let engine, case let .prompting(p) = engine.state, ui.micAccepts(p.card, midi: midi) else { return false }
        // Both clocks are monotonic; map the onset onto the engine clock (error < 1 ms while awake).
        let ago = max(0, MicAnswerController.hostNowSeconds - onsetHostSeconds)
        let onset = engine.clockNow - .nanoseconds(Int64(ago * 1e9))
        env.haptics.grade(correct: true)
        apply(engine.answerDetected(at: onset))
        return true
    }

    /// After the timeout, reveal for manual grading (the mic may have missed a correct note).
    private func armMicTimeout() {
        micTimeoutTask?.cancel()
        guard mic != nil, case let .prompting(p) = state else { return }
        let id = p.presentationID
        let seconds = config.micTimeoutSeconds
        micTimeoutTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled, let self, case let .prompting(cur) = self.state, cur.presentationID == id else { return }
            self.ok()
        }
    }

    func stopMic() {
        micTimeoutTask?.cancel()
        mic?.stop()
        mic = nil
    }

    // MARK: Internals

    private func syncState() {
        guard let engine else { return }
        state = engine.state
        if case let .prompting(p) = state { prepare(p) }
        // Listen only while a prompt is visible (not during reveal / pause / playback).
        if case .prompting = state { mic?.setListening(true) } else { mic?.setListening(false); micTimeoutTask?.cancel() }
    }

    private func apply(_ effects: [SessionEffect]) {
        recorder?.record(effects)
        syncState()
        if case .finished = state, let recorder {
            self.recorder = nil
            stopMic()
            let env = env
            Task {
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
