import Foundation

/// Startup guard (DEBUG) that pins the persisted JSON shape of `SessionConfig`,
/// `DeckOptions` and `SessionLength`. Not a test target: it runs at app launch.
public enum PersistedFormatCheck {
    /// M1 data (no `tuning`, `inputMode`, `micTimeoutSeconds` keys). Checked by decode only:
    /// re-encoding adds the newer keys.
    static let legacyFixtures: [(json: String, expected: SessionConfig)] = [
        (
            #"{"deckID":"music.fretboard.notes","focus":"strong","length":{"minutes":{"_0":5}},"options":{"fretboard":{"_0":{"accidentalSpelling":"mixed","fretRange":[0,15],"noteSet":"all","strings":[1,6]}}},"retryWrongCards":false}"#,
            SessionConfig(
                deckID: FretboardNotesDeck.deckID,
                options: .fretboard(FretboardOptions(strings: [1, 6], noteSet: .all, accidentalSpelling: .mixed, fretRange: 0...15)),
                length: .minutes(5), focus: .strong, retryWrongCards: false
            )
        ),
        (
            #"{"deckID":"ko.aion2","focus":"normal","length":{"cards":{"_0":30}},"options":{"vocab":{"_0":{"autoPlayAudio":true,"direction":"both","newPerSession":5,"tags":["combat"]}}},"retryWrongCards":true}"#,
            SessionConfig(
                deckID: "ko.aion2",
                options: .vocab(VocabOptions(direction: .both, newPerSession: 5, tags: ["combat"])),
                length: .cards(30)
            )
        ),
    ]

    /// Current format (M2, plus the M3 option cases). Checked by decode and byte-identical `.sortedKeys` re-encode.
    static let fixtures: [(json: String, expected: SessionConfig)] = [
        (
            #"{"deckID":"music.fretboard.notes","focus":"strong","inputMode":"microphone","length":{"minutes":{"_0":5}},"micTimeoutSeconds":20,"options":{"fretboard":{"_0":{"accidentalSpelling":"mixed","fretRange":[0,15],"noteSet":"all","strings":[1,6],"tuning":"dropD"}}},"retryWrongCards":false}"#,
            SessionConfig(
                deckID: FretboardNotesDeck.deckID,
                options: .fretboard(FretboardOptions(strings: [1, 6], noteSet: .all, accidentalSpelling: .mixed, fretRange: 0...15, tuning: .dropD)),
                length: .minutes(5), focus: .strong, retryWrongCards: false, inputMode: .microphone, micTimeoutSeconds: 20
            )
        ),
        (
            #"{"deckID":"music.fretboard.intervals","focus":"normal","inputMode":"touch","length":{"cards":{"_0":10}},"micTimeoutSeconds":10,"options":{"intervals":{"_0":{"accidentalSpelling":"flats","fretRange":[1,9],"intervals":["M3","P5"],"strings":[5,6],"tuning":"standard"}}},"retryWrongCards":true}"#,
            SessionConfig(
                deckID: IntervalsDeck.deckID,
                options: .intervals(IntervalOptions(intervals: [.M3, .P5], strings: [5, 6], fretRange: 1...9, tuning: .standard, accidentalSpelling: .flats)),
                length: .cards(10)
            )
        ),
        (
            #"{"deckID":"music.ear.intervals","focus":"off","inputMode":"touch","length":{"cards":{"_0":20}},"micTimeoutSeconds":10,"options":{"earIntervals":{"_0":{"intervals":["m3","TT"],"mode":"harm","rootRange":[50,62]}}},"retryWrongCards":true}"#,
            SessionConfig(
                deckID: EarIntervalsDeck.deckID,
                options: .earIntervals(EarIntervalOptions(intervals: [.m3, .TT], mode: .harmonic, rootRange: 50...62)),
                length: .cards(20), focus: .off
            )
        ),
        // M3 option cases.
        (
            #"{"deckID":"music.chords.play","focus":"normal","inputMode":"touch","length":{"cards":{"_0":10}},"micTimeoutSeconds":10,"options":{"chords":{"_0":{"families":["barre","open"],"maxFret":9,"qualities":["maj","min7"],"roots":[0,10]}}},"retryWrongCards":true}"#,
            SessionConfig(deckID: ChordsPlayDeck.deckID, options: .chords(ChordOptions(families: [.open, .barre], qualities: [.maj, .min7], roots: [PitchClass(0), PitchClass(10)], maxFret: 9)), length: .cards(10))
        ),
        (
            #"{"deckID":"music.triads","focus":"normal","inputMode":"touch","length":{"cards":{"_0":10}},"micTimeoutSeconds":10,"options":{"triads":{"_0":{"inversions":["first"],"maxFret":12,"qualities":["maj"],"roots":[0],"stringSets":["123"]}}},"retryWrongCards":true}"#,
            SessionConfig(deckID: TriadsDeck.deckID, options: .triads(TriadOptions(qualities: [.maj], inversions: [.first], stringSets: [.s123], roots: [PitchClass(0)], maxFret: 12)), length: .cards(10))
        ),
        (
            #"{"deckID":"music.arpeggios","focus":"normal","inputMode":"touch","length":{"cards":{"_0":10}},"micTimeoutSeconds":10,"options":{"arpeggios":{"_0":{"maxFret":12,"qualities":["min7"],"rootStrings":[6],"roots":[9],"span":"oneOctave"}}},"retryWrongCards":true}"#,
            SessionConfig(deckID: ArpeggiosDeck.deckID, options: .arpeggios(ArpeggioOptions(qualities: [.min7], rootStrings: [6], roots: [PitchClass(9)], span: .oneOctave, maxFret: 12)), length: .cards(10))
        ),
        (
            #"{"deckID":"music.scales","focus":"normal","inputMode":"touch","length":{"cards":{"_0":10}},"micTimeoutSeconds":10,"options":{"scales":{"_0":{"maxFret":15,"systems":["box"],"tonics":[9],"types":["dorian","minorPentatonic"]}}},"retryWrongCards":true}"#,
            SessionConfig(deckID: ScalesDeck.deckID, options: .scales(ScaleOptions(types: [.minorPentatonic, .dorian], systems: [.box], tonics: [PitchClass(9)], maxFret: 15)), length: .cards(10))
        ),
        (
            #"{"deckID":"music.theory.keysig","focus":"normal","inputMode":"touch","length":{"cards":{"_0":10}},"micTimeoutSeconds":10,"options":{"keySignatures":{"_0":{"directions":["sigToKey"],"modes":["minor"]}}},"retryWrongCards":true}"#,
            SessionConfig(deckID: KeySignaturesDeck.deckID, options: .keySignatures(KeySigOptions(modes: [.minor], directions: [.sigToKey])), length: .cards(10))
        ),
        (
            #"{"deckID":"music.theory.diatonic","focus":"normal","inputMode":"touch","length":{"cards":{"_0":10}},"micTimeoutSeconds":10,"options":{"diatonic":{"_0":{"chordSize":"both","directions":["degreeToChord"],"keys":["Bb","G"],"modes":["major","minor"]}}},"retryWrongCards":true}"#,
            SessionConfig(deckID: DiatonicDeck.deckID, options: .diatonic(DiatonicOptions(modes: [.major, .minor], chordSize: .both, directions: [.degreeToChord], keys: ["Bb", "G"])), length: .cards(10))
        ),
        (
            #"{"deckID":"music.progressions","focus":"normal","inputMode":"touch","length":{"cards":{"_0":10}},"micTimeoutSeconds":10,"options":{"progressions":{"_0":{"bluesFourBars":true,"keys":["G"],"progressions":["blues12","ii-V-I"],"voicingStyle":"caged"}}},"retryWrongCards":true}"#,
            SessionConfig(deckID: ProgressionsDeck.deckID, options: .progressions(ProgressionOptions(progressions: [.twoFiveOne, .blues12], keys: ["G"], voicingStyle: .caged, bluesFourBars: true)), length: .cards(10))
        ),
        (
            #"{"deckID":"music.theory.circle","focus":"normal","inputMode":"touch","length":{"cards":{"_0":10}},"micTimeoutSeconds":10,"options":{"circle":{"_0":{"questions":["fifthAbove","relativeMinor"]}}},"retryWrongCards":true}"#,
            SessionConfig(deckID: CircleOfFifthsDeck.deckID, options: .circle(CircleOptions(questions: [.fifthAbove, .relativeMinor])), length: .cards(10))
        ),
        // M4-0 answer modes, M4-3 listening directions.
        (
            #"{"deckID":"ko.core.1","focus":"normal","inputMode":"touch","length":{"cards":{"_0":20}},"micTimeoutSeconds":10,"options":{"vocab":{"_0":{"autoPlayAudio":false,"direction":"allThree","newPerSession":5,"tags":["food"]}}},"retryWrongCards":true}"#,
            SessionConfig(deckID: "ko.core.1", options: .vocab(VocabOptions(direction: .allThree, newPerSession: 5, autoPlayAudio: false, tags: ["food"])))
        ),
        (
            #"{"deckID":"ko.core.1","focus":"normal","inputMode":"touch","length":{"cards":{"_0":20}},"micTimeoutSeconds":10,"options":{"vocab":{"_0":{"autoPlayAudio":true,"direction":"listening","newPerSession":10,"tags":[]}}},"retryWrongCards":true}"#,
            SessionConfig(deckID: "ko.core.1", options: .vocab(VocabOptions(direction: .listening)))
        ),
        (
            #"{"deckID":"ko.core.1","focus":"normal","inputMode":"typed","length":{"cards":{"_0":20}},"micTimeoutSeconds":10,"options":{"vocab":{"_0":{"autoPlayAudio":true,"direction":"both","newPerSession":10,"tags":[]}}},"retryWrongCards":true}"#,
            SessionConfig(deckID: "ko.core.1", options: .vocab(VocabOptions(direction: .both)), inputMode: .typed)
        ),
        (
            #"{"deckID":"music.chords.name","focus":"normal","inputMode":"choice","length":{"cards":{"_0":10}},"micTimeoutSeconds":10,"options":{"chords":{"_0":{"families":["open"],"maxFret":12,"qualities":["maj"],"roots":[0]}}},"retryWrongCards":true}"#,
            SessionConfig(deckID: ChordsNameDeck.deckID, options: .chords(ChordOptions(families: [.open], qualities: [.maj], roots: [PitchClass(0)], maxFret: 12)), length: .cards(10), inputMode: .choice)
        ),
        // M4-2 Hangul reading.
        (
            #"{"deckID":"ko.hangul","focus":"normal","inputMode":"typed","length":{"cards":{"_0":20}},"micTimeoutSeconds":10,"options":{"hangulReading":{"_0":{"newPerSession":6,"stages":["batchim","realWords","syllables"]}}},"retryWrongCards":true}"#,
            SessionConfig(deckID: HangulReadingDeck.deckID, options: .hangulReading(HangulReadingOptions(stages: [.syllables, .batchim, .realWords], newPerSession: 6)), inputMode: .typed)
        ),
        // M4-5 particles.
        (
            #"{"deckID":"ko.particles","focus":"normal","inputMode":"choice","length":{"cards":{"_0":20}},"micTimeoutSeconds":10,"options":{"particles":{"_0":{"nounSource":"coreOnly","particles":["direction","topic"]}}},"retryWrongCards":true}"#,
            SessionConfig(deckID: ParticlesDeck.deckID, options: .particles(ParticleOptions(particles: [.topic, .direction], nounSource: .coreOnly)), inputMode: .choice)
        ),
        // M4-6 conjugation.
        (
            #"{"deckID":"ko.conjugation","focus":"normal","inputMode":"typed","length":{"cards":{"_0":20}},"micTimeoutSeconds":10,"options":{"conjugation":{"_0":{"forms":["negativePolite","pastPolite","presentPolite"],"newPerSession":7,"source":"core1"}}},"retryWrongCards":true}"#,
            SessionConfig(deckID: ConjugationDeck.deckID, options: .conjugation(ConjugationOptions(forms: [.presentPolite, .pastPolite, .negativePolite], source: .core1, newPerSession: 7)), inputMode: .typed)
        ),
    ]

    /// Returns human-readable errors (empty = format intact).
    public static func run() -> [String] {
        let decoder = JSONDecoder()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        var errors: [String] = []

        func decode(_ json: String, _ expected: SessionConfig, _ label: String) -> SessionConfig? {
            do {
                let decoded = try decoder.decode(SessionConfig.self, from: Data(json.utf8))
                if decoded != expected { errors.append("\(label): decoded value differs") }
                if !decoded.recoveredFields.isEmpty { errors.append("\(label): recovered \(decoded.recoveredFields.sorted())") }
                return decoded
            } catch {
                errors.append("\(label): \(error)")
                return nil
            }
        }

        for (i, f) in legacyFixtures.enumerated() {
            _ = decode(f.json, f.expected, "legacy fixture \(i)")
        }
        for (i, f) in fixtures.enumerated() {
            guard let decoded = decode(f.json, f.expected, "fixture \(i)") else { continue }
            do {
                let reencoded = String(decoding: try encoder.encode(decoded), as: UTF8.self)
                if reencoded != f.json { errors.append("fixture \(i): re-encoded JSON differs:\n\(reencoded)") }
            } catch {
                errors.append("fixture \(i): \(error)")
            }
        }
        #if DEBUG
        errors += HangulReadingDeck.selfCheck()
        errors += ParticlesDeck.selfCheck()
        errors += ConjugationDeck.selfCheck()
        errors += UserDecks.selfCheck()
        errors += ScreenshotWords.selfCheck()
        #endif
        return errors
    }
}
