/// How accidentals are written.
public enum AccidentalSpelling: String, Codable, Sendable, CaseIterable {
    case sharps, flats, mixed

    /// Deterministic spelling (mixed → sharp), used when generating base cards.
    public func baseSpelling(_ pc: PitchClass) -> NoteSpelling {
        .preferred(for: pc, preferFlat: self == .flats)
    }

    /// Random spelling for presentation (only `.mixed` is random).
    public func presentationSpelling(_ pc: PitchClass, using rng: inout SplitMix64) -> NoteSpelling {
        guard self == .mixed, !pc.isNatural else { return baseSpelling(pc) }
        return .preferred(for: pc, preferFlat: Bool.random(using: &rng))
    }
}

/// ItemKey namespacing for fretboard decks.
public enum FretboardKeys {
    /// Standard tuning keeps the bare scheme forever (`fret`); other tunings are prefixed
    /// (`fret@dropD`). Never change this rule: stats are joined on keys.
    public static func scheme(_ base: String, tuning: TuningID) -> String {
        tuning == .standard ? base : "\(base)@\(tuning.rawValue)"
    }
}

/// Display helpers shared by fretboard decks.
public enum FretboardText {
    /// "6–1", "6, 4, 3" — strings in descending order.
    public static func strings(_ strings: some Collection<Int>) -> String {
        let s = strings.sorted(by: >)
        guard let first = s.first, let last = s.last else { return "" }
        let contiguous = s.count > 1 && zip(s, s.dropFirst()).allSatisfy { $0 - 1 == $1 }
        if contiguous { return "\(first)–\(last)" }
        return s.map(String.init).joined(separator: ", ")
    }

    /// "frets 0–12"
    public static func frets(_ r: ClosedRange<Int>) -> String { "frets \(r.lowerBound)–\(r.upperBound)" }
}

/// Tolerant decoding helper for option structs.
extension KeyedDecodingContainer {
    @inlinable func tolerant<T: Decodable>(_ type: T.Type, _ key: Key, _ fallback: T) -> T {
        (try? decodeIfPresent(T.self, forKey: key)) ?? fallback
    }
}
