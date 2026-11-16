import Foundation
import MemoriseCore
import Observation

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

    @ObservationIgnored private let env: AppEnvironment
    @ObservationIgnored private var engine: SessionEngine?
    @ObservationIgnored private var recorder: SessionRecorder?

    init(env: AppEnvironment, deck: any Deck, config: SessionConfig) {
        self.env = env
        self.deck = deck
        self.config = config
    }

    // MARK: Derived

    var countedGraded: Int { engine?.countedGraded ?? 0 }
    var progress: Double { engine?.progress ?? 0 }
    var maxFret: Int { config.options.fretboard?.fretRange.upperBound ?? 12 }

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
            apply(engine.start())
        } catch {
            loadError = error.localizedDescription
        }
    }

    func promptDidAppear() { engine?.promptDidAppear() }

    func ok() {
        guard let engine, case .prompting = engine.state else { return }
        engine.ok()
        env.haptics.ok()
        state = engine.state
        autoPlayIfNeeded()
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
        state = engine.state
    }

    func quit() {
        guard let engine else { return }
        env.speech.stop()
        apply(engine.quit())
    }

    func speak(_ text: String) { env.speech.speak(text, rate: env.settings.speechRate) }

    // MARK: Internals

    private func apply(_ effects: [SessionEffect]) {
        guard let engine else { return }
        recorder?.record(effects)
        state = engine.state
        if case .finished = state, let recorder {
            self.recorder = nil
            let env = env
            Task {
                await recorder.close()
                env.dataDidChange()
            }
        }
    }

    private func autoPlayIfNeeded() {
        guard case let .revealed(p, _) = state, let vocab = p.card.vocab else { return }
        guard env.speech.hasKoreanVoice else {
            if !env.settings.koreanVoiceHintShown {
                env.settings.koreanVoiceHintShown = true
                showVoiceHint = true
            }
            return
        }
        if env.settings.autoPlayPronunciation, config.options.vocab?.autoPlayAudio ?? true {
            speak(vocab.entry.hangul)
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
