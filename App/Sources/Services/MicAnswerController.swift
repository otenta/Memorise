import AVFoundation
import MemoriseCore
import Observation

/// Runs the microphone + pitch detector for a session and reports stable notes.
///
/// A note is **stable** when the same MIDI note (±40 cents) is detected in 3 consecutive frames;
/// its onset is the host time of the first frame of that run.
@MainActor @Observable
final class MicAnswerController {
    enum Permission { case unknown, granted, denied }

    /// Smoothed input level in dBFS (for the meter).
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
    // Stability tracking.
    @ObservationIgnored private var runMidi: Int?
    @ObservationIgnored private var runCount = 0
    @ObservationIgnored private var runOnset = 0.0
    @ObservationIgnored private var reportedMidi: Int?
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
        let detector = PitchDetector(sampleRate: format.sampleRate) { [weak self] frame in
            Task { @MainActor [weak self] in self?.handle(frame) }
        }
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
        detector = nil
        isRunning = false
        isListening = false
        audio.endRecording()
    }

    /// Enables/disables matching (on while a prompt is visible; off during reveal and playback).
    func setListening(_ on: Bool) {
        guard on != isListening else { return }
        isListening = on
        resetRun()
        reportedMidi = nil
        heardWrong = nil
    }

    // MARK: Frames

    private func handle(_ f: PitchFrame) {
        levelDB = 0.7 * levelDB + 0.3 * max(f.rmsDB, -80)
        guard isListening else { return }
        guard let midi = f.midi, abs(f.cents) <= Self.centsTolerance else {
            resetRun()
            if f.midi == nil { reportedMidi = nil }
            return
        }
        if midi == runMidi {
            runCount += 1
        } else {
            runMidi = midi
            runCount = 1
            runOnset = f.hostSeconds
        }
        guard runCount == Self.stableFrames, midi != reportedMidi else { return }
        reportedMidi = midi
        if onStableNote?(midi, runOnset) == true {
            setListening(false)
        } else {
            showWrong(midi)
        }
    }

    private func resetRun() {
        runMidi = nil
        runCount = 0
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
