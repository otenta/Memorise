import AVFoundation
import MemoriseCore
import Observation

/// Runs the microphone + pitch detector for a session and reports stable notes.
///
/// A note is **stable** when the same MIDI note (±40 cents) is detected in 3 consecutive frames;
/// its onset is the host time of the first frame of that run.
///
/// Frames (≈ 94/s at 48 kHz) are tracked on the detector queue by `MicFrameTracker`; the main
/// actor only hears about stable notes and a throttled level (R4-5).
@MainActor @Observable
final class MicAnswerController {
    enum Permission { case unknown, granted, denied }

    /// Smoothed input level in dBFS (for the meter). Published at ≤ 20 Hz, only while listening
    /// and only when it moves by more than 1 dB.
    private(set) var levelDB: Double = -80
    /// Transient "Heard G♯" text for a stable but wrong note.
    private(set) var heardWrong: String?
    /// Whether frames are currently being matched (prompt visible).
    private(set) var isListening = false
    private(set) var isRunning = false

    /// Called on a stable note. Return true when it answered the card (stops listening).
    @ObservationIgnored var onStableNote: ((_ midi: Int, _ onsetHostSeconds: Double) -> Bool)?

    @ObservationIgnored private let audio: AudioSessionCoordinator
    @ObservationIgnored private let engine = AVAudioEngine()
    @ObservationIgnored private var detector: PitchDetector?
    @ObservationIgnored private let tracker = MicFrameTracker(stableFrames: MicAnswerController.stableFrames,
                                                              centsTolerance: MicAnswerController.centsTolerance)
    @ObservationIgnored private var wrongClearTask: Task<Void, Never>?

    static let stableFrames = 3
    static let centsTolerance = 40.0

    init(audio: AudioSessionCoordinator) {
        self.audio = audio
    }

    // MARK: Permission

    static var permission: Permission {
        switch AVAudioApplication.shared.recordPermission {
        case .granted: .granted
        case .denied: .denied
        default: .unknown
        }
    }

    /// Requests mic access if undetermined. Returns whether it is granted.
    static func requestPermission() async -> Bool {
        if permission == .granted { return true }
        if permission == .denied { return false }
        return await AVAudioApplication.requestRecordPermission()
    }

    // MARK: Lifecycle

    /// Starts the input engine (record session). Throws if the audio session or engine fails.
    func start() throws {
        guard !isRunning else { return }
        try audio.beginRecording()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        let tracker = tracker
        let detector = PitchDetector(sampleRate: format.sampleRate) { [weak self] frame in
            // Detector queue: track here, hop to main only for something to show or act on.
            let out = tracker.process(frame)
            if let level = out.level {
                Task { @MainActor [weak self] in self?.publishLevel(level) }
            }
            if let note = out.stable {
                Task { @MainActor [weak self] in self?.deliver(note) }
            }
        }
        detector.setActive(isListening)
        self.detector = detector
        Self.installTap(on: input, format: format, detector: detector)
        try engine.start()
        isRunning = true
    }

    /// Tap closures run on an audio thread, so they must not be main-actor isolated.
    private nonisolated static func installTap(on input: AVAudioInputNode, format: AVAudioFormat, detector: PitchDetector) {
        input.installTap(onBus: 0, bufferSize: AVAudioFrameCount(PitchDetector.hop * 2), format: format) { buffer, time in
            detector.process(buffer, time: time)
        }
    }

    func stop() {
        guard isRunning else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        detector?.setActive(false)
        detector = nil
        isRunning = false
        isListening = false
        audio.endRecording()
    }

    /// Enables/disables matching (on while a prompt is visible; off during reveal and playback).
    func setListening(_ on: Bool) {
        guard on != isListening else { return }
        isListening = on
        tracker.setListening(on, at: Self.hostNowSeconds)
        detector?.setActive(on)
        heardWrong = nil
    }

    // MARK: Main-actor delivery

    private func publishLevel(_ level: Double) {
        guard isListening else { return }
        levelDB = level
    }

    private func deliver(_ note: MicFrameTracker.StableNote) {
        // Drop notes from a listening window that has since closed (reveal, next card).
        guard isListening, note.generation == tracker.generation else { return }
        if onStableNote?(note.midi, note.onsetHostSeconds) == true {
            setListening(false)
        } else {
            showWrong(note.midi)
        }
    }

    private func showWrong(_ midi: Int) {
        heardWrong = Pitch(midi: midi).name(spelling: .preferred(for: PitchClass(midi), preferFlat: false))
        wrongClearTask?.cancel()
        wrongClearTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            self?.heardWrong = nil
        }
    }

    /// Current host-clock time in seconds.
    static var hostNowSeconds: Double { AVAudioTime.seconds(forHostTime: mach_absolute_time()) }
}

/// Stability tracking and level smoothing, run on the detector queue (R4-5).
///
/// `process` is called from the detector's serial queue; `setListening` / `generation` from the
/// main actor. All state is guarded by one lock (uncontended in practice; work per frame is tiny).
final class MicFrameTracker: @unchecked Sendable {
    struct StableNote: Sendable {
        let midi: Int
        let onsetHostSeconds: Double
        /// Listening window the note belongs to.
        let generation: Int
    }

    struct Output: Sendable {
        /// New level to publish, if due.
        var level: Double?
        var stable: StableNote?
    }

    /// Minimum seconds between level publications (≤ 20 Hz).
    static let levelInterval = 0.05
    /// Minimum level change worth publishing, in dB.
    static let levelStepDB = 1.0

    private let stableFrames: Int
    private let centsTolerance: Double
    private let lock = NSLock()

    private var listening = false
    private var currentGeneration = 0
    private var runMidi: Int?
    private var runCount = 0
    private var runOnset = 0.0
    private var reportedMidi: Int?
    private var level = -80.0
    private var publishedLevel = -80.0
    private var publishedAt = -Double.infinity
    /// Host seconds when listening was last armed; earlier windows hold the previous card's audio.
    private var armedAt = -Double.infinity

    init(stableFrames: Int, centsTolerance: Double) {
        self.stableFrames = stableFrames
        self.centsTolerance = centsTolerance
    }

    /// Bumped on every listening change; stale stable notes are dropped on main. Frames whose
    /// analysis window starts before arming (`windowStartSeconds < armedAt`) are ignored on the
    /// detector queue, so audio from before the prompt can't answer the card (R6-3).
    var generation: Int { lock.withLock { currentGeneration } }

    /// `hostSeconds` is the arming time on the same host clock as `PitchFrame` times.
    func setListening(_ on: Bool, at hostSeconds: Double) {
        lock.withLock {
            listening = on
            armedAt = on ? hostSeconds : -.infinity
            currentGeneration += 1
            runMidi = nil
            runCount = 0
            reportedMidi = nil
        }
    }

    func process(_ f: PitchFrame) -> Output {
        lock.withLock {
            var out = Output()
            level = 0.7 * level + 0.3 * max(f.rmsDB, -80)
            guard listening else { return out }
            if f.hostSeconds - publishedAt >= Self.levelInterval, abs(level - publishedLevel) > Self.levelStepDB {
                publishedAt = f.hostSeconds
                publishedLevel = level
                out.level = level
            }
            // R6-3: a window that starts before arming holds the previous card's audio.
            guard f.windowStartSeconds >= armedAt else { return out }
            guard let midi = f.midi, abs(f.cents) <= centsTolerance else {
                runMidi = nil
                runCount = 0
                if f.midi == nil { reportedMidi = nil }
                return out
            }
            if midi == runMidi {
                runCount += 1
            } else {
                runMidi = midi
                runCount = 1
                runOnset = f.hostSeconds
            }
            guard runCount == stableFrames, midi != reportedMidi else { return out }
            reportedMidi = midi
            out.stable = StableNote(midi: midi, onsetHostSeconds: runOnset, generation: currentGeneration)
            return out
        }
    }
}
