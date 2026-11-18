import AVFoundation

/// The thread-safe part of text-to-speech: every call on the synthesizer happens on one serial queue, in call
/// order (PLAN_R11 PA3). Tests substitute a stub.
protocol SpeechEngining: AnyObject, Sendable {
    /// Called on an arbitrary thread when an utterance finished or was cancelled.
    var onEnded: (@Sendable (ObjectIdentifier) -> Void)? { get set }
    /// Stops anything speaking and speaks `utterance`. `beforeSpeaking` runs on the queue first.
    func speak(_ utterance: AVSpeechUtterance, beforeSpeaking: (@Sendable () -> Void)?)
    func stop()
    /// Resumes once the queue has run the stop.
    func stopAndWait() async
}

/// `AVSpeechSynthesizer` on a private serial queue. `@unchecked Sendable`: the synthesizer is only touched there.
final class SpeechEngine: NSObject, SpeechEngining, AVSpeechSynthesizerDelegate, @unchecked Sendable {
    private let queue = DispatchQueue(label: "memorise.speech", qos: .userInitiated)
    private var synthesizerStorage: AVSpeechSynthesizer?
    var onEnded: (@Sendable (ObjectIdentifier) -> Void)?

    /// Created on first use, on the queue.
    private var synthesizer: AVSpeechSynthesizer {
        if let synthesizerStorage { return synthesizerStorage }
        let s = AVSpeechSynthesizer()
        s.delegate = self
        synthesizerStorage = s
        return s
    }

    func speak(_ utterance: AVSpeechUtterance, beforeSpeaking: (@Sendable () -> Void)?) {
        nonisolated(unsafe) let utterance = utterance
        queue.async { [self] in
            beforeSpeaking?()
            Perf.interval("speech.speak") {
                if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
                synthesizer.speak(utterance)
            }
        }
    }

    func stop() {
        queue.async { [self] in stopNow() }
    }

    func stopAndWait() async {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                stopNow()
                continuation.resume()
            }
        }
    }

    private func stopNow() {
        Perf.interval("speech.stop") {
            if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
        }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        onEnded?(ObjectIdentifier(utterance))
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        onEnded?(ObjectIdentifier(utterance))
    }
}

/// On-device text-to-speech: Korean for vocab, English for short feedback words (R7-F3).
/// The main actor only builds the utterance and enqueues; the synthesizer and the audio session run elsewhere.
@MainActor
final class SpeechService {
    private let engine: any SpeechEngining
    private let audio: AudioSessionCoordinator
    private var koreanVoice = AVSpeechSynthesisVoice(language: "ko-KR")
    private lazy var englishVoice = AVSpeechSynthesisVoice(language: AVSpeechSynthesisVoice.currentLanguageCode().hasPrefix("en") ? AVSpeechSynthesisVoice.currentLanguageCode() : "en-US")
        ?? AVSpeechSynthesisVoice(language: "en-US")
    /// Completion for the utterance currently being spoken.
    private var pending: (id: ObjectIdentifier, utterance: AVSpeechUtterance, onFinish: @MainActor () -> Void)?

    init(audio: AudioSessionCoordinator, engine: any SpeechEngining = SpeechEngine()) {
        self.audio = audio
        self.engine = engine
        engine.onEnded = { [weak self] id in
            Task { @MainActor [weak self] in self?.utteranceEnded(id) }
        }
    }

    /// Whether a Korean voice is installed.
    var hasKoreanVoice: Bool { koreanVoice != nil }

    /// Re-queries installed voices (the user may have downloaded one while the app was in background).
    func refreshVoices() {
        koreanVoice = AVSpeechSynthesisVoice(language: "ko-KR")
    }

    /// Speaks Korean text, interrupting anything currently spoken.
    ///
    /// `onFinish` runs on the main actor when this utterance finishes, is cancelled by a later
    /// `speak`/`stop`, or immediately when no Korean voice is installed.
    func speak(_ text: String, rate: Double, onFinish: (@MainActor () -> Void)? = nil) {
        speak(text, voice: koreanVoice, rate: Float(rate), onFinish: onFinish)
    }

    /// Speaks a short English phrase ("Correct", "Try again") at the normal rate, interrupting
    /// anything currently spoken. `onFinish` follows the same rules as `speak`.
    func speakEnglish(_ text: String, onFinish: (@MainActor () -> Void)? = nil) {
        speak(text, voice: englishVoice, rate: AVSpeechUtteranceDefaultSpeechRate, onFinish: onFinish)
    }

    /// Loads the Korean voice and the audio session before the first reveal, by speaking a silent utterance.
    /// Call it after the first prompt is on screen. Does nothing without a Korean voice.
    func prewarm() {
        guard let koreanVoice else { return }
        audio.ensurePlayback()
        let utterance = AVSpeechUtterance(string: " ")
        utterance.voice = koreanVoice
        utterance.volume = 0
        // Not tracked in `pending`: a real `speak` replaces it, and its cancellation matches nothing.
        enqueue(utterance)
    }

    private func speak(_ text: String, voice: AVSpeechSynthesisVoice?, rate: Float, onFinish: (@MainActor () -> Void)?) {
        guard let voice else {
            onFinish?()
            return
        }
        audio.ensurePlayback()
        finishPending()
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice
        utterance.rate = rate
        if let onFinish { pending = (ObjectIdentifier(utterance), utterance, onFinish) }
        enqueue(utterance)
    }

    private func enqueue(_ utterance: AVSpeechUtterance) {
        // The queue waits for the audio session before it speaks, so the first word isn't played under the
        // default category.
        let audio = audio
        engine.speak(utterance) { audio.waitUntilIdle() }
    }

    /// Stops speaking. Returns at once.
    func stop() {
        finishPending()
        engine.stop()
    }

    /// Stops speaking and resumes once the engine has actually stopped (the mic must not hear the tail).
    func stopAndWait() async {
        finishPending()
        await engine.stopAndWait()
    }

    private func finishPending() {
        guard let p = pending else { return }
        pending = nil
        p.onFinish()
    }

    private func utteranceEnded(_ id: ObjectIdentifier) {
        guard let p = pending, p.id == id else { return }
        finishPending()
    }
}
