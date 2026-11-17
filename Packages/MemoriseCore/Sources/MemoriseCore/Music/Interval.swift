import Foundation

/// Simple intervals up to an octave. Raw values appear in `ItemKey`s — **never change them**.
public enum Interval: String, Codable, Sendable, CaseIterable, Hashable, Comparable {
    case m2, M2, m3, M3, P4, TT, P5, m6, M6, m7, M7, P8

    public var semitones: Int {
        switch self {
        case .m2: 1
        case .M2: 2
        case .m3: 3
        case .M3: 4
        case .P4: 5
        case .TT: 6
        case .P5: 7
        case .m6: 8
        case .M6: 9
        case .m7: 10
        case .M7: 11
        case .P8: 12
        }
    }

    /// Letter distance (the tritone is spelled as an augmented 4th).
    public var letterSteps: Int {
        switch self {
        case .m2, .M2: 1
        case .m3, .M3: 2
        case .P4, .TT: 3
        case .P5: 4
        case .m6, .M6: 5
        case .m7, .M7: 6
        case .P8: 7
        }
    }

    /// "M3"
    public var shortName: String { self == .TT ? "TT" : rawValue }

    /// "major 3rd"
    public var longName: String {
        switch self {
        case .m2: "minor 2nd"
        case .M2: "major 2nd"
        case .m3: "minor 3rd"
        case .M3: "major 3rd"
        case .P4: "perfect 4th"
        case .TT: "tritone"
        case .P5: "perfect 5th"
        case .m6: "minor 6th"
        case .M6: "major 6th"
        case .m7: "minor 7th"
        case .M7: "major 7th"
        case .P8: "octave"
        }
    }

    public static let defaultSet: Set<Interval> = [.m3, .M3, .P4, .P5, .P8]

    public static func < (lhs: Interval, rhs: Interval) -> Bool { lhs.semitones < rhs.semitones }
}

public extension NoteSpelling {
    /// Spelling of the note `interval` above this one, or `nil` if it would need a double accidental.
    ///
    /// C + M3 = E; E + M3 = G♯; B♭ + P4 = E♭; F + TT = B; A♯ + M3 → nil (C𝄪).
    func transposed(by interval: Interval) -> NoteSpelling? {
        let letters = NoteLetter.allCases
        let target = letters[(letter.rawValue + interval.letterSteps) % letters.count]
        let wanted = pitchClass.transposed(by: interval.semitones)
        // Signed distance in -6…5 from the natural letter to the wanted pitch class.
        var diff = (wanted.value - target.pitchClass.value) % 12
        if diff > 6 { diff -= 12 }
        if diff < -6 { diff += 12 }
        switch diff {
        case 0: return NoteSpelling(target, .natural)
        case 1: return NoteSpelling(target, .sharp)
        case -1: return NoteSpelling(target, .flat)
        default: return nil
        }
    }
}

/// A concrete pitch (MIDI note number, 12-TET, A4 = 440 Hz).
public struct Pitch: Hashable, Sendable, Comparable {
    public let midi: Int

    public init(midi: Int) { self.midi = midi }

    public var pitchClass: PitchClass { PitchClass(midi) }

    /// Scientific octave: MIDI 60 = C4.
    public var octave: Int { Int((Double(midi) / 12).rounded(.down)) - 1 }

    public var frequency: Double { Self.frequency(midi: Double(midi)) }

    @inlinable public static func frequency(midi: Double) -> Double {
        440 * pow(2, (midi - 69) / 12)
    }

    /// Nearest pitch to a frequency and the deviation in cents (−50…50).
    public static func nearest(toFrequency hz: Double) -> (pitch: Pitch, cents: Double) {
        let exact = 69 + 12 * log2(max(hz, 1e-6) / 440)
        let rounded = exact.rounded()
        return (Pitch(midi: Int(rounded)), (exact - rounded) * 100)
    }

    /// e.g. "A2" with the given spelling for the pitch class.
    public func name(spelling: NoteSpelling) -> String { "\(spelling.displayName)\(octave)" }

    public static func < (lhs: Pitch, rhs: Pitch) -> Bool { lhs.midi < rhs.midi }
}
