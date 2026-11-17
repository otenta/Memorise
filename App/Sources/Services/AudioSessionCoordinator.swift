import AVFoundation

/// Single owner of the shared `AVAudioSession` category.
///
/// - Playback (TTS, synth): `.playback` + `.mixWithOthers` — plays through the silent switch (D3)
///   and keeps the user's music playing.
/// - Recording (microphone answers): `.playAndRecord` + `.measurement` + `.defaultToSpeaker`,
///   only while a mic session is running.
@MainActor
final class AudioSessionCoordinator {
    enum Mode { case playback, recording }

    private(set) var mode: Mode?
    private let session = AVAudioSession.sharedInstance()

    /// Activates playback unless recording is already active (never downgrades a mic session).
    func ensurePlayback() {
        guard mode == nil else { return }
        do {
            try session.setCategory(.playback, mode: .spokenAudio, options: [.mixWithOthers])
            try session.setActive(true)
            mode = .playback
        } catch {
            AppEnvironment.log.error("Audio playback session failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Switches to record mode for a microphone session.
    func beginRecording() throws {
        try session.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker, .mixWithOthers, .allowBluetoothA2DP])
        try session.setActive(true)
        mode = .recording
    }

    /// Ends a microphone session (and any playback).
    func endRecording() {
        guard mode == .recording else { return }
        deactivate()
    }

    /// Releases the session so other apps' audio returns to full volume.
    func deactivate() {
        guard mode != nil else { return }
        try? session.setActive(false, options: .notifyOthersOnDeactivation)
        mode = nil
    }
}
