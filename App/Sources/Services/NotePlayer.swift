import AVFoundation
import os

/// Offline plucked-string note playback (Karplus–Strong on an `AVAudioSourceNode`).
@MainActor
final class NotePlayer {
    private let audio: AudioSessionCoordinator
    private let engine = AVAudioEngine()
    private let synth: PluckSynth
    private var started = false

    /// Output gain 0…1 (applied on top of the −6 dBFS peak), read on every `play`.
    var volume: @MainActor () -> Float = { 0.8 }

    init(audio: AudioSessionCoordinator, sampleRate: Double = 48_000) {
        self.audio = audio
        synth = PluckSynth(sampleRate: sampleRate)
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        let node = Self.makeNode(synth: synth, format: format)
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
        engine.prepare()
    }

    /// Built outside the main actor so the render block is not main-actor isolated
    /// (it runs on the real-time audio thread).
    private nonisolated static func makeNode(synth: PluckSynth, format: AVAudioFormat) -> AVAudioSourceNode {
        AVAudioSourceNode(format: format) { isSilence, _, frameCount, bufferList in
            synth.render(frameCount: Int(frameCount), bufferList: bufferList, isSilence: isSilence)
        }
    }

    /// Plays one note now.
    func play(midi: Int) { play([(midi, 0)]) }

    /// Strums a chord low → high.
    func strum(_ midis: [Int], spacing: Double = 0.03, at start: Double = 0) {
        play(Self.strumEvents(midis, spacing: spacing, at: start))
    }

    /// Plays notes one after another (scales, arpeggios).
    func sequence(_ midis: [Int], spacing: Double = 0.25) {
        play(midis.enumerated().map { ($1, Double($0) * spacing) })
    }

    /// One strum per chord on the beat.
    func progression(_ chords: [[Int]], beat: Double = 0.9) {
        play(Self.progressionEvents(chords, beat: beat))
    }

    static func strumEvents(_ midis: [Int], spacing: Double = 0.03, at start: Double = 0) -> [(midi: Int, delay: Double)] {
        midis.sorted().enumerated().map { ($1, start + Double($0) * spacing) }
    }

    static func progressionEvents(_ chords: [[Int]], beat: Double = 0.9) -> [(midi: Int, delay: Double)] {
        chords.enumerated().flatMap { strumEvents($1, at: Double($0) * beat) }
    }

    /// Plays notes with start offsets (seconds). Up to 6 voices sound at once; voices are
    /// assigned when each note starts, so long sequences don't steal their own later notes.
    func play(_ notes: [(midi: Int, delay: Double)]) {
        guard !notes.isEmpty else { return }
        audio.ensurePlayback()
        synth.setVolume(volume())
        if !started || !engine.isRunning {
            do {
                try engine.start()
                started = true
            } catch {
                AppEnvironment.log.error("Note engine failed: \(error.localizedDescription, privacy: .public)")
                return
            }
        }
        synth.enqueue(notes)
    }

    /// Stops the engine (call when audio is deactivated).
    func stop() {
        guard started else { return }
        engine.stop()
        started = false
    }
}

/// Real-time synth state. All buffers are allocated up front; the render thread never allocates
/// and only *tries* the lock (a contended cycle simply picks up queued notes on the next one).
private final class PluckSynth: @unchecked Sendable {
    private struct Voice {
        var active = false
        var pending = false
        var startIn = 0          // samples until start (pending)
        var midi = 0
        var length = 2           // delay-line length N
        var index = 0
        var age = 0              // samples since start
        var last: Float = 0      // averaging filter state
        var apX1: Float = 0      // fractional-delay allpass state
        var apY1: Float = 0
        var apC: Float = 0
    }

    static let voiceCount = 6
    static let pendingCapacity = 256
    static let maxLength = 4_096
    static let decay: Float = 0.996

    private let sampleRate: Double
    private let attack: Int
    private let duration: Int
    private let release: Int
    private let voices: UnsafeMutablePointer<Voice>
    private let lines: UnsafeMutablePointer<Float>
    /// Render-thread queue of notes waiting for their start sample.
    private let pending: UnsafeMutablePointer<(midi: Int, startAt: Int)>
    private var pendingCount = 0
    /// Samples rendered so far.
    private var clock = 0
    private var rng: UInt64 = 0x9E37_79B9_7F4A_7C15

    /// Shared with the main thread. The render thread only uses `withLockIfAvailable`.
    private struct Shared: Sendable {
        var notes: [Note] = []
        var volume: Float = 0.8
    }

    private struct Note: Sendable {
        let midi: Int
        let delay: Int
    }

    private let shared: OSAllocatedUnfairLock<Shared>
    private var gain: Float = 0.5 * 0.8

    init(sampleRate: Double) {
        self.sampleRate = sampleRate
        attack = Int(sampleRate * 0.002)
        duration = Int(sampleRate * 1.6)
        release = Int(sampleRate * 0.03)
        voices = .allocate(capacity: Self.voiceCount)
        voices.initialize(repeating: Voice(), count: Self.voiceCount)
        lines = .allocate(capacity: Self.voiceCount * Self.maxLength)
        lines.initialize(repeating: 0, count: Self.voiceCount * Self.maxLength)
        var initial = Shared()
        initial.notes.reserveCapacity(Self.pendingCapacity)
        pending = .allocate(capacity: Self.pendingCapacity)
        pending.initialize(repeating: (0, 0), count: Self.pendingCapacity)
        shared = OSAllocatedUnfairLock(initialState: initial)
    }

    deinit {
        voices.deallocate()
        lines.deallocate()
        pending.deallocate()
    }

    // MARK: Main thread

    func enqueue(_ notes: [(midi: Int, delay: Double)]) {
        let sr = sampleRate
        let incoming = notes.map { Note(midi: $0.midi, delay: Int(max(0, $0.delay) * sr)) }
        shared.withLock { s in
            for n in incoming where s.notes.count < Self.pendingCapacity { s.notes.append(n) }
        }
    }

    func setVolume(_ v: Float) {
        let clamped = max(0, min(1, v))
        shared.withLock { $0.volume = clamped }
    }

    // MARK: Render thread

    func render(frameCount: Int, bufferList: UnsafeMutablePointer<AudioBufferList>, isSilence: UnsafeMutablePointer<ObjCBool>) -> OSStatus {
        shared.withLockIfAvailable { s in
            self.gain = 0.5 * s.volume // −6 dBFS peak × volume
            for n in s.notes where self.pendingCount < Self.pendingCapacity {
                self.pending[self.pendingCount] = (n.midi, self.clock + n.delay)
                self.pendingCount += 1
            }
            s.notes.removeAll(keepingCapacity: true)
        }
        // Assign voices to notes starting within this buffer.
        let bufferEnd = clock + frameCount
        var i = 0
        while i < pendingCount {
            if pending[i].startAt < bufferEnd {
                schedule(midi: pending[i].midi, startIn: max(0, pending[i].startAt - clock))
                pendingCount -= 1
                pending[i] = pending[pendingCount]
            } else {
                i += 1
            }
        }
        clock = bufferEnd

        let abl = UnsafeMutableAudioBufferListPointer(bufferList)
        guard let out = abl.first?.mData?.assumingMemoryBound(to: Float.self) else { return noErr }
        var anyActive = pendingCount > 0
        for f in 0..<frameCount {
            var sample: Float = 0
            for v in 0..<Self.voiceCount {
                sample += step(v)
            }
            out[f] = max(-1, min(1, sample * gain))
        }
        for v in 0..<Self.voiceCount where voices[v].active || voices[v].pending { anyActive = true }
        if !anyActive { isSilence.pointee = true }
        // Copy to any extra channels.
        for b in abl.dropFirst() {
            b.mData?.copyMemory(from: out, byteCount: Int(b.mDataByteSize))
        }
        return noErr
    }

    private func schedule(midi: Int, startIn: Int) {
        // Free voice, else steal the oldest.
        var target = 0
        var oldest = -1
        for v in 0..<Self.voiceCount {
            if !voices[v].active && !voices[v].pending { target = v; oldest = Int.max; break }
            if voices[v].age > oldest { oldest = voices[v].age; target = v }
        }
        voices[target] = Voice(pending: true, startIn: startIn, midi: midi)
    }

    @inline(__always)
    private func step(_ v: Int) -> Float {
        if voices[v].pending {
            if voices[v].startIn > 0 { voices[v].startIn -= 1; return 0 }
            excite(v)
        }
        guard voices[v].active else { return 0 }
        let line = lines + v * Self.maxLength
        let n = voices[v].length
        let i = voices[v].index
        let x = line[i]
        // Two-tap average (½-sample delay) + fractional allpass for exact tuning.
        let avg = 0.5 * (x + voices[v].last)
        voices[v].last = x
        let c = voices[v].apC
        let ap = c * avg + voices[v].apX1 - c * voices[v].apY1
        voices[v].apX1 = avg
        voices[v].apY1 = ap
        line[i] = ap * Self.decay
        voices[v].index = i + 1 == n ? 0 : i + 1

        let age = voices[v].age
        voices[v].age = age + 1
        var env: Float = 1
        if age < attack { env = Float(age) / Float(attack) }
        let remaining = duration - age
        if remaining < release { env = max(0, Float(remaining) / Float(release)) }
        if remaining <= 0 { voices[v].active = false }
        return x * env
    }

    /// Starts a voice: sets the delay length for the pitch and fills it with low-passed noise.
    private func excite(_ v: Int) {
        let freq = 440 * pow(2, Double(voices[v].midi - 69) / 12)
        // Loop delay = N + 0.5 (averager) + d (allpass) = sampleRate / freq.
        let p = sampleRate / freq - 0.5
        var n = Int(p)
        var d = p - Double(n)
        if d < 0.1 { n -= 1; d += 1 }
        n = max(2, min(Self.maxLength, n))
        let line = lines + v * Self.maxLength
        var prev: Float = 0
        for k in 0..<n {
            rng = rng &* 6364136223846793005 &+ 1442695040888963407
            let noise = Float(Int32(truncatingIfNeeded: rng >> 32)) / Float(Int32.max)
            line[k] = 0.5 * (noise + prev)
            prev = noise
        }
        voices[v].length = n
        voices[v].index = 0
        voices[v].age = 0
        voices[v].last = 0
        voices[v].apX1 = 0
        voices[v].apY1 = 0
        voices[v].apC = Float((1 - d) / (1 + d))
        voices[v].pending = false
        voices[v].active = true
    }
}
