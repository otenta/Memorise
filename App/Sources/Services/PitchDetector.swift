import Accelerate
import AVFoundation
import MemoriseCore
import os

/// One analysed frame.
struct PitchFrame: Sendable {
    /// Nearest MIDI note, `nil` when gated (too quiet) or no clear pitch.
    let midi: Int?
    let cents: Double
    /// 1 − CMNDF minimum (0…1).
    let confidence: Double
    /// Host-clock seconds of the start of the frame's newest hop (the onset estimate, R4-7).
    ///
    /// The window's first sample would bias onsets early by up to a window (≈ 43 ms at 48 kHz),
    /// because a run's first detecting frame usually starts before the note. The hop start can be
    /// late by up to one hop (≈ 11 ms) when the note began earlier in the window (PLAN §17).
    let hostSeconds: Double
    /// Host-clock seconds of the oldest sample in the analysed window.
    ///
    /// Frames whose window starts before the tracker was armed hold pre-prompt audio (R6-3).
    let windowStartSeconds: Double
    /// Frame RMS in dBFS (for the level meter).
    let rmsDB: Double
}

/// YIN pitch detector: 2048-sample frames, 512-sample hop, threshold 0.12 with parabolic
/// interpolation, −45 dBFS gate, 70–1 400 Hz. Runs on a private serial queue.
final class PitchDetector: @unchecked Sendable {
    static let frameLength = 2_048
    static let hop = 512
    static let window = 1_024
    static let threshold = 0.12
    static let gateDB = -45.0
    static let minHz = 70.0
    static let maxHz = 1_400.0

    let sampleRate: Double
    private let queue = DispatchQueue(label: "memorise.pitch", qos: .userInteractive)
    private let onFrame: @Sendable (PitchFrame) -> Void
    /// Whether frames are analysed (R5-3). Off during reveal, pause and playback: the ring keeps
    /// filling so re-arming has a full frame at once, but YIN is skipped.
    private let active = OSAllocatedUnfairLock(initialState: false)

    // Queue-confined state (preallocated).
    private var ring: [Float]
    private var filled = 0
    private var sinceHop = 0
    private var diff: [Float]
    private let tauMin: Int
    private let tauMax: Int

    init(sampleRate: Double, onFrame: @escaping @Sendable (PitchFrame) -> Void) {
        self.sampleRate = sampleRate
        self.onFrame = onFrame
        ring = [Float](repeating: 0, count: Self.frameLength)
        tauMin = max(2, Int(sampleRate / Self.maxHz))
        tauMax = min(Self.frameLength - Self.window - 1, Int(sampleRate / Self.minHz))
        diff = [Float](repeating: 0, count: tauMax + 2)
    }

    /// Feeds an input buffer (any thread). Samples are copied before hopping to the queue.
    func process(_ buffer: AVAudioPCMBuffer, time: AVAudioTime) {
        guard let data = buffer.floatChannelData?[0] else { return }
        let n = Int(buffer.frameLength)
        let samples = Array(UnsafeBufferPointer(start: data, count: n))
        let startHost = AVAudioTime.seconds(forHostTime: time.hostTime)
        let sr = sampleRate
        queue.async { [self] in
            append(samples, newestHostSeconds: startHost + Double(n - 1) / sr)
        }
    }

    /// Turns analysis on or off (any thread).
    func setActive(_ on: Bool) { active.withLock { $0 = on } }

    private var isActive: Bool { active.withLock { $0 } }

    // MARK: Queue

    private func append(_ samples: [Float], newestHostSeconds: Double) {
        var i = 0
        while i < samples.count {
            let take = min(Self.hop - sinceHop, samples.count - i)
            // Shift the ring left and append (frameLength is small; memmove is cheap).
            ring.withUnsafeMutableBufferPointer { r in
                let base = r.baseAddress!
                base.update(from: base + take, count: Self.frameLength - take)
                samples.withUnsafeBufferPointer { s in
                    (base + Self.frameLength - take).update(from: s.baseAddress! + i, count: take)
                }
            }
            i += take
            sinceHop += take
            filled = min(Self.frameLength, filled + take)
            if sinceHop == Self.hop {
                sinceHop = 0
                if filled == Self.frameLength, isActive {
                    let newest = newestHostSeconds - Double(samples.count - i) / sampleRate
                    analyse(newestHostSeconds: newest)
                }
            }
        }
    }

    private func analyse(newestHostSeconds: Double) {
        // Analyse `ring` in place: it is queue-confined and not mutated until the next append.
        let hostSeconds = newestHostSeconds - Double(Self.hop - 1) / sampleRate
        let windowStart = newestHostSeconds - Double(Self.frameLength - 1) / sampleRate

        var rms: Float = 0
        vDSP_rmsqv(ring, 1, &rms, vDSP_Length(Self.frameLength))
        let rmsDB = 20 * log10(Double(max(rms, 1e-9)))
        guard rmsDB >= Self.gateDB else {
            onFrame(PitchFrame(midi: nil, cents: 0, confidence: 0, hostSeconds: hostSeconds,
                               windowStartSeconds: windowStart, rmsDB: rmsDB))
            return
        }

        // Difference function d(τ) = Σ (x[j] − x[j+τ])², j < W.
        let w = vDSP_Length(Self.window)
        ring.withUnsafeBufferPointer { x in
            diff.withUnsafeMutableBufferPointer { d in
                d[0] = 0
                for tau in 1...tauMax {
                    var sum: Float = 0
                    vDSP_distancesq(x.baseAddress!, 1, x.baseAddress! + tau, 1, &sum, w)
                    d[tau] = sum
                }
            }
        }

        // Cumulative-mean-normalised difference (in place) + absolute threshold.
        var running: Float = 0
        var best = -1
        diff[0] = 1
        for tau in 1...tauMax {
            running += diff[tau]
            diff[tau] = running > 0 ? diff[tau] * Float(tau) / running : 1
        }
        var tau = tauMin
        while tau <= tauMax {
            if Double(diff[tau]) < Self.threshold {
                while tau + 1 <= tauMax && diff[tau + 1] < diff[tau] { tau += 1 }
                best = tau
                break
            }
            tau += 1
        }
        guard best > 0 else {
            onFrame(PitchFrame(midi: nil, cents: 0, confidence: 0, hostSeconds: hostSeconds,
                               windowStartSeconds: windowStart, rmsDB: rmsDB))
            return
        }

        // Parabolic interpolation around the minimum.
        var refined = Double(best)
        if best > 1 && best < tauMax {
            let a = Double(diff[best - 1]), b = Double(diff[best]), c = Double(diff[best + 1])
            let denom = a - 2 * b + c
            if abs(denom) > 1e-12 { refined += 0.5 * (a - c) / denom }
        }
        let hz = sampleRate / refined
        guard hz >= Self.minHz, hz <= Self.maxHz else {
            onFrame(PitchFrame(midi: nil, cents: 0, confidence: 0, hostSeconds: hostSeconds,
                               windowStartSeconds: windowStart, rmsDB: rmsDB))
            return
        }
        let (pitch, cents) = Pitch.nearest(toFrequency: hz)
        onFrame(PitchFrame(midi: pitch.midi, cents: cents, confidence: 1 - Double(diff[best]), hostSeconds: hostSeconds,
                           windowStartSeconds: windowStart, rmsDB: rmsDB))
    }
}
