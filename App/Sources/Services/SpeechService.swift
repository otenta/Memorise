import AVFoundation

/// On-device Korean text-to-speech.
@MainActor
final class SpeechService {
    private let synthesizer = AVSpeechSynthesizer()
    private var sessionConfigured = false
    private var koreanVoice = AVSpeechSynthesisVoice(language: "ko-KR")

    /// Whether a Korean voice is installed.
    var hasKoreanVoice: Bool { koreanVoice != nil }

    /// Re-queries installed voices (the user may have downloaded one while the app was in background).
    func refreshVoices() {
        koreanVoice = AVSpeechSynthesisVoice(language: "ko-KR")
    }

    /// Releases the audio session so other apps' audio returns to full volume.
    func deactivate() {
        guard sessionConfigured else { return }
        stop()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        sessionConfigured = false
    }

    /// Speaks Korean text, interrupting anything currently spoken.
    func speak(_ text: String, rate: Double) {
        guard let voice = koreanVoice else { return }
        configureAudioSessionIfNeeded()
        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice
        utterance.rate = Float(rate)
        synthesizer.speak(utterance)
    }

    func stop() {
        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
    }

    /// `.playback` + `.mixWithOthers` so the user's music keeps playing.
    private func configureAudioSessionIfNeeded() {
        guard !sessionConfigured else { return }
        sessionConfigured = true
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .spokenAudio, options: [.mixWithOthers])
        try? session.setActive(true)
    }
}
