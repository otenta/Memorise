import Testing
@testable import MemoriseCore

/// PLAN §7.1 — theory primitives.
@Suite("Music theory (§7.1)")
struct MusicTheoryTests {
    @Test func pitchClassNormalisesModulo12() {
        #expect(PitchClass(12).value == 0)
        #expect(PitchClass(-1).value == 11)
        #expect(PitchClass(-25).value == 11)
        #expect(PitchClass(40).value == 4) // E2
        #expect(PitchClass(11).transposed(by: 2).value == 1)
        #expect(PitchClass.allCases.count == 12)
        #expect(PitchClass.naturals.map(\.value) == [0, 2, 4, 5, 7, 9, 11])
    }

    @Test func canonicalSharpNamesAreAsciiAndStable() {
        #expect(PitchClass.allCases.map(\.canonicalSharpName)
            == ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"])
    }

    @Test func spellingPitchClassAndDisplay() {
        #expect(NoteSpelling(.c, .sharp).pitchClass == NoteSpelling(.d, .flat).pitchClass)
        #expect(NoteSpelling(.c, .flat).pitchClass.value == 11) // C♭ = B
        #expect(NoteSpelling(.b, .sharp).pitchClass.value == 0) // B♯ = C
        #expect(NoteSpelling(.c, .sharp).displayName == "C♯")
        #expect(NoteSpelling(.b, .flat).displayName == "B♭")
        #expect(!NoteSpelling(.c, .sharp).displayName.contains("#"))
    }

    @Test(arguments: PitchClass.allCases)
    func preferredSpellingRoundTrips(pc: PitchClass) {
        let sharp = NoteSpelling.preferred(for: pc, preferFlat: false)
        let flat = NoteSpelling.preferred(for: pc, preferFlat: true)
        #expect(sharp.pitchClass == pc)
        #expect(flat.pitchClass == pc)
        if pc.isNatural {
            #expect(sharp.accidental == .natural && flat.accidental == .natural)
        } else {
            #expect(sharp.accidental == .sharp)
            #expect(flat.accidental == .flat)
        }
    }

    @Test func formatterMatchesSpecExamples() {
        let a = NoteSpelling(.a)
        #expect(NoteFormatter.format(a, naming: .letter) == "A")
        #expect(NoteFormatter.format(a, naming: .solfege) == "La")
        #expect(NoteFormatter.format(a, naming: .both) == "A (La)")
        #expect(NoteFormatter.format(NoteSpelling(.c, .sharp), naming: .both) == "C♯ (Do♯)")
        #expect(NoteFormatter.format(NoteSpelling(.b, .flat), naming: .solfege) == "Si♭")
        #expect(NoteFormatter.format(NoteSpelling(.b, .flat), naming: .solfege, variant: .ti) == "Ti♭")
        #expect(NoteFormatter.format(NoteSpelling(.g), settings: .default) == "G (Sol)")
        #expect(MusicDisplaySettings.default.naming == .both)
    }

    @Test func standardTuning() {
        let t = Tuning.standard
        #expect(t.openMidi == [40, 45, 50, 55, 59, 64])
        #expect(t.stringNumbers == [6, 5, 4, 3, 2, 1])
        #expect(t.openMidi(string: 6) == 40)
        #expect(t.openMidi(string: 1) == 64)
        #expect((1...6).map(t.stringName) == ["high E", "B", "G", "D", "A", "low E"])
    }

    @Test func stringNamesDeriveFromOpenNotes() {
        #expect((1...6).map(Tuning.dropD.stringName) == ["high E", "B", "G", "D", "A", "low D"])
        #expect(Tuning.halfDown.stringName(6) == "low E♭")
        #expect(Tuning.openG.stringName(5) == "G")
        for id in TuningID.allCases { #expect(Tuning.preset(id).id == id) }
    }

    @Test func fretsMatchSpecExamples() {
        let a = NoteLetter.a.pitchClass, e = NoteLetter.e.pitchClass
        #expect(Fretboard.frets(for: a, onString: 6, fretRange: 0...12) == [5])
        #expect(Fretboard.frets(for: a, onString: 6, fretRange: 0...22) == [5, 17])
        #expect(Fretboard.frets(for: e, onString: 6, fretRange: 0...12) == [0, 12])
        #expect(Fretboard.frets(for: e, onString: 6, fretRange: 1...12) == [12])
        #expect(Fretboard.frets(for: e, onString: 6, fretRange: 1...11) == [])
        #expect(Fretboard.frets(for: a, onString: 6, fretRange: 6...24) == [17])
    }

    @Test func fretsAgreeWithPitchAtPosition() {
        for s in 1...6 {
            for pc in PitchClass.allCases {
                let frets = Fretboard.frets(for: pc, onString: s, fretRange: 0...24)
                #expect(frets.count == 2 || frets.count == 3)
                for f in frets { #expect(Fretboard.pitchClass(string: s, fret: f) == pc) }
            }
        }
    }

    @Test func everyPitchClassExistsOnEveryStringWhenMaxFretAtLeast11() {
        for s in 1...6 {
            for pc in PitchClass.allCases {
                #expect(!Fretboard.frets(for: pc, onString: s, fretRange: 0...11).isEmpty)
            }
        }
    }
}
