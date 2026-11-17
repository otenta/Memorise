import Foundation

/// Chord shape family. Raw values are persisted in options — **never change them**.
public enum ShapeFamily: String, Codable, Sendable, CaseIterable, Hashable {
    case open, barre, caged, power, other

    public var title: String {
        switch self {
        case .open: "Open"
        case .barre: "Barre"
        case .caged: "CAGED"
        case .power: "Power"
        case .other: "dim7 / aug"
        }
    }
}

/// A chord fingering from `Resources/Shapes/chord_shapes.json`. Ids appear in `ItemKey`s —
/// **never change or reuse them**.
public struct ChordShape: Codable, Hashable, Sendable, Identifiable {
    public struct Barre: Codable, Hashable, Sendable {
        /// Relative to the root fret for movable shapes, absolute for open shapes.
        public let fret: Int
        public let fromString: Int
        public let toString: Int
    }

    public let id: String
    public let family: ShapeFamily
    public let cagedShape: String?
    public let quality: ChordQuality
    public let rootString: Int
    public let movable: Bool
    /// ASCII root of open shapes ("C").
    public let root: String?
    /// String 6 → 1; `nil` = muted. Relative to the root fret for movable shapes.
    public let frets: [Int?]
    public let fingers: [Int?]
    public let barre: Barre?

    /// Index into `frets` for string number `n` (6 → 0).
    @inlinable public static func index(ofString n: Int) -> Int { 6 - n }

    public var rootSpelling: NoteSpelling? { root.flatMap(NoteSpelling.init(ascii:)) }

    /// "A-shape barre", "CAGED C shape", "open", "power chord · root on 6"
    public var hint: String {
        switch family {
        case .open: "open chord"
        case .barre: "\(cagedShape ?? "")-shape barre"
        case .caged: "CAGED \(cagedShape ?? "") shape"
        case .power: "power chord · root on \(rootString)"
        case .other: "root on string \(rootString)"
        }
    }

    /// Lowest relative offset of a sounded string.
    var minOffset: Int { frets.compactMap { $0 }.min() ?? 0 }
    var maxOffset: Int { frets.compactMap { $0 }.max() ?? 0 }

    /// Lowest-position voicing for `root` with every fret ≤ `maxFret`.
    public func voicing(root: NoteSpelling, tuning: Tuning = .standard, maxFret: Int) -> Voicing? {
        voicings(root: root, tuning: tuning, maxFret: maxFret).first
    }

    /// Every position of this shape for `root` up to `maxFret`, lowest first.
    public func voicings(root: NoteSpelling, tuning: Tuning = .standard, maxFret: Int) -> [Voicing] {
        guard let chord = Chord(root: root, quality: quality) else { return [] }
        if !movable {
            guard let own = rootSpelling, own.pitchClass == root.pitchClass,
                  maxOffset <= maxFret else { return [] }
            return [makeVoicing(absolute: frets, barre: barre, chord: chord, tuning: tuning)]
        }
        let open = tuning.openPitchClass(string: rootString)
        var f = PitchClass(root.pitchClass.value - open.value).value
        // Movable shapes are fingered above the nut: every sounded fret ≥ 1.
        while f + minOffset < 1 { f += 12 }
        var result: [Voicing] = []
        while f + maxOffset <= maxFret {
            let abs = frets.map { $0.map { $0 + f } }
            let b = barre.map { Barre(fret: $0.fret + f, fromString: $0.fromString, toString: $0.toString) }
            result.append(makeVoicing(absolute: abs, barre: b, chord: chord, tuning: tuning))
            f += 12
        }
        return result
    }

    private func makeVoicing(absolute: [Int?], barre: Barre?, chord: Chord, tuning: Tuning) -> Voicing {
        var midis: [Int] = []
        var labels: [String?] = []
        for (i, fret) in absolute.enumerated() {
            let s = 6 - i
            if let fret {
                let midi = Fretboard.midi(string: s, fret: fret, tuning: tuning)
                midis.append(midi)
                labels.append(chord.degreeLabel(for: PitchClass(midi)))
            } else {
                labels.append(nil)
            }
        }
        return Voicing(shapeID: id, chord: chord, frets: absolute, fingers: fingers, barre: barre, midis: midis, degreeLabels: labels)
    }
}

/// A shape placed on the neck for a concrete chord.
public struct Voicing: Hashable, Sendable {
    public let shapeID: String
    public let chord: Chord
    /// Absolute frets, string 6 → 1; `nil` = muted.
    public let frets: [Int?]
    public let fingers: [Int?]
    public let barre: ChordShape.Barre?
    /// Sounding notes, low → high.
    public let midis: [Int]
    /// Degree label per string (6 → 1).
    public let degreeLabels: [String?]

    public init(shapeID: String, chord: Chord, frets: [Int?], fingers: [Int?], barre: ChordShape.Barre?, midis: [Int], degreeLabels: [String?]) {
        self.shapeID = shapeID
        self.chord = chord
        self.frets = frets
        self.fingers = fingers
        self.barre = barre
        self.midis = midis
        self.degreeLabels = degreeLabels
    }

    /// Lowest fretted (non-open) fret, or 0 when everything is open.
    public var lowestFret: Int { frets.compactMap { $0 }.filter { $0 > 0 }.min() ?? 0 }
    public var highestFret: Int { frets.compactMap { $0 }.max() ?? 0 }

    /// Mean of the fretted positions (for nearest-position voice leading).
    public var centre: Double {
        let f = frets.compactMap { $0 }.filter { $0 > 0 }
        return f.isEmpty ? 0 : Double(f.reduce(0, +)) / Double(f.count)
    }

    /// Lowest → highest sounded string numbers.
    public var soundedStrings: [Int] { frets.enumerated().compactMap { $0.element == nil ? nil : 6 - $0.offset } }

    /// "x-1-3-1-2-1"
    public var tab: String { frets.map { $0.map(String.init) ?? "x" }.joined(separator: "-") }
}

/// The bundled chord shapes, validated once at first use.
public struct ChordShapeLibrary: Sendable {
    public let shapes: [ChordShape]
    public let warnings: [String]

    public static let shared: ChordShapeLibrary = load()

    public func shape(id: String) -> ChordShape? { shapes.first { $0.id == id } }

    private struct File: Decodable {
        let schemaVersion: Int
        let shapes: [ChordShape]
    }

    static func load() -> ChordShapeLibrary {
        guard let url = Bundle.module.url(forResource: "chord_shapes", withExtension: "json", subdirectory: "Shapes") else {
            return ChordShapeLibrary(shapes: [], warnings: ["Shapes/chord_shapes.json: missing"])
        }
        do {
            let file = try JSONDecoder().decode(File.self, from: Data(contentsOf: url))
            let (valid, warnings) = ShapeValidator.validate(file.shapes)
            return ChordShapeLibrary(shapes: valid, warnings: warnings)
        } catch {
            return ChordShapeLibrary(shapes: [], warnings: ["Shapes/chord_shapes.json: \(error.localizedDescription)"])
        }
    }
}
