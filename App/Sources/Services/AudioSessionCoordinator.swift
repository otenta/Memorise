import AVFoundation

/// Single owner of the shared `AVAudioSession` category.
///
/// - Playback (TTS, synth): `.playback` + `.mixWithOthers` — plays through the silent switch (D3)
///   and keeps the user's music playing.
/// - Recording (microphone answers): `.playAndRecord` + `.measurement` + `.defaultToSpeaker`,
///   only while a mic session is running.
///
/// `setCategory` and `setActive` block, so playback activation and deactivation run on one private serial
/// queue (PLAN_R11 PA3). `mode` is bookkeeping on the main actor, set before the work is dispatched.
@MainActor
final class AudioSessionCoordinator {
    enum Mode { case playback, recording }

    private(set) var mode: Mode?
    private nonisolated let session = AVAudioSession.sharedInstance()
    private nonisolated let queue = DispatchQueue(label: "memorise.audio-session", qos: .userInitiated)

    /// Activates playback unless recording is already active (never downgrades a mic session).
    /// Returns at once; the session is ready once the queue has run (`waitUntilIdle`).
    func ensurePlayback() {
        guard mode == nil else { return }
        mode = .playback
        let session = session
        queue.async { [weak self] in
            do {
                try Perf.interval("audio.activate") {
                    try session.setCategory(.playback, mode: .spokenAudio, options: [.mixWithOthers])
                    try session.setActive(true)
                }
            } catch {
                AppEnvironment.log.error("Audio playback session failed: \(error.localizedDescription, privacy: .public)")
                Task { @MainActor [weak self] in
                    if self?.mode == .playback { self?.mode = nil }
                }
            }
        }
    }

    /// Blocks until every queued activation or deactivation has run. Call it off the main thread
    /// (the speech queue does, before it speaks), never from the main actor.
    nonisolated func waitUntilIdle() {
        queue.sync {}
    }

    /// Switches to record mode for a microphone session. Synchronous: the mic needs the session ready, so it
    /// waits for any queued playback activation first. Called at session start, not per card.
    func beginRecording() throws {
        let session = session
        try queue.sync {
            try session.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker, .mixWithOthers, .allowBluetoothA2DP])
            try session.setActive(true)
        }
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
        mode = nil
        let session = session
        queue.async {
            try? session.setActive(false, options: .notifyOthersOnDeactivation)
        }
    }
}
