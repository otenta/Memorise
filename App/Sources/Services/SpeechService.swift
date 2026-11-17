import AVFoundation

/// On-device text-to-speech: Korean for vocab, English for short feedback words (R7-F3).
@MainActor
final class SpeechService: NSObject {
    private let synthesizer = AVSpeechSynthesizer()
    private let audio: AudioSessionCoordinator
    private var koreanVoice = AVSpeechSynthesisVoice(language: "ko-KR")
    private lazy var englishVoice = AVSpeechSynthesisVoice(language: AVSpeechSynthesisVoice.currentLanguageCode().hasPrefix("en") ? AVSpeechSynthesisVoice.currentLanguageCode() : "en-US")
        ?? AVSpeechSynthesisVoice(language: "en-US")
    /// Completion for the utterance currently being spoken.
    private var pending: (utterance: AVSpeechUtterance, onFinish: @MainActor () -> Void)?

    init(audio: AudioSessionCoordinator) {
        self.audio = audio
        super.init()
        synthesizer.delegate = self
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

    private func speak(_ text: String, voice: AVSpeechSynthesisVoice?, rate: Float, onFinish: (@MainActor () -> Void)?) {
        guard let voice else {
            onFinish?()
            return
        }
        audio.ensurePlayback()
        finishPending()
        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice
        utterance.rate = rate
        if let onFinish { pending = (utterance, onFinish) }
        synthesizer.speak(utterance)
    }

    func stop() {
        finishPending()
        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
    }

    private func finishPending() {
        guard let p = pending else { return }
        pending = nil
        p.onFinish()
    }

    fileprivate func utteranceEnded(_ utterance: AVSpeechUtterance) {
        guard let p = pending, p.utterance === utterance else { return }
        finishPending()
    }
}

extension SpeechService: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        nonisolated(unsafe) let u = utterance
        Task { @MainActor in self.utteranceEnded(u) }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        nonisolated(unsafe) let u = utterance
        Task { @MainActor in self.utteranceEnded(u) }
    }
}
