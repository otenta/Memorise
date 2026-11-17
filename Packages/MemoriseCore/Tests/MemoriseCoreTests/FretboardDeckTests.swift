import Testing
@testable import MemoriseCore

/// PLAN §7.2, F2 (P1-1 mixed spelling).
@Suite("Fretboard Notes deck (§7.2, F2)")
struct FretboardDeckTests {
    let deck = FretboardNotesDeck()

    @Test func cardCountsMatchSpec() {
        #expect(fretboardCards().count == 42)
        #expect(fretboardCards(FretboardOptions(noteSet: .all)).count == 72)
        #expect(fretboardCards(FretboardOptions(strings: [5, 6])).count == 14)
        #expect(fretboardCards(FretboardOptions(strings: [])).isEmpty)
    }

    @Test func cardsWithoutAnAnswerFretInRangeAreDropped() {
        // Low E, frets 0…4: E F F♯ G G♯ → naturals E, F, G.
        let cards = fretboardCards(FretboardOptions(strings: [6], fretRange: 0...4))
        #expect(cards.map(\.key.raw).sorted() == ["fret:s6:E", "fret:s6:F", "fret:s6:G"])
    }

    @Test func itemKeyFormat() {
        #expect(FretboardNotesDeck.itemKey(string: 6, pitchClass: NoteLetter.a.pitchClass).raw == "fret:s6:A")
        #expect(FretboardNotesDeck.itemKey(string: 3, pitchClass: PitchClass(1)).raw == "fret:s3:C#")
        #expect(Set(fretboardCards(FretboardOptions(noteSet: .all)).map(\.key)).count == 72)
    }

    @Test func keysAreSpellingIndependent() {
        let keys = FretboardOptions.AccidentalSpelling.allCases.map { spelling in
            fretboardCards(FretboardOptions(noteSet: .all, accidentalSpelling: spelling)).map(\.key)
        }
        #expect(keys[0] == keys[1])
        #expect(keys[1] == keys[2])
    }

    @Test func answerFretsCoverEveryMatchInRange() {
        let cards = fretboardCards(FretboardOptions(fretRange: 0...22))
        let a6 = cards.first { $0.key == "fret:s6:A" }?.fretboardNote
        #expect(a6?.answerFrets == [5, 17])
        let e1 = cards.first { $0.key == "fret:s1:E" }?.fretboardNote
        #expect(e1?.answerFrets == [0, 12])
    }

    // MARK: F2 — spelling at presentation time

    private func presentedAccidentals(_ spelling: FretboardOptions.AccidentalSpelling, draws: Int = 1_000, seed: UInt64 = 42) -> (sharps: Int, flats: Int) {
        let options = FretboardOptions(noteSet: .all, accidentalSpelling: spelling)
        let accidentals = fretboardCards(options)
            .filter { !$0.fretboardNote!.pitchClass.isNatural }
        var rng = SplitMix64(seed: seed)
        var sharps = 0, flats = 0
        for i in 0..<draws {
            let shown = deck.present(accidentals[i % accidentals.count], options: .fretboard(options), using: &rng).fretboardNote!
            #expect(shown.spelling.pitchClass == shown.pitchClass, "re-spelling must not change the pitch")
            switch shown.spelling.accidental {
            case .sharp: sharps += 1
            case .flat: flats += 1
            case .natural: Issue.record("accidental pitch presented as natural")
            case .doubleFlat, .doubleSharp: Issue.record("fretboard notes must never use double accidentals")
            }
        }
        return (sharps, flats)
    }

    @Test func sharpsNeverPresentsFlats() {
        let r = presentedAccidentals(.sharps)
        #expect(r.flats == 0)
        #expect(r.sharps == 1_000)
    }

    @Test func flatsNeverPresentsSharps() {
        let r = presentedAccidentals(.flats)
        #expect(r.sharps == 0)
        #expect(r.flats == 1_000)
    }

    @Test(arguments: [1, 7, 42] as [UInt64])
    func mixedPresentsBothSpellingsRoughlyEvenly(seed: UInt64) {
        let r = presentedAccidentals(.mixed, seed: seed)
        let share = Double(r.flats) / Double(r.flats + r.sharps)
        #expect((0.35...0.65).contains(share), "flat share \(share)")
    }

    @Test func presentKeepsKeyAndNaturalsUntouched() {
        var rng = SplitMix64(seed: 3)
        let options = FretboardOptions(noteSet: .all, accidentalSpelling: .mixed)
        for card in fretboardCards(options) {
            let shown = deck.present(card, options: .fretboard(options), using: &rng)
            #expect(shown.key == card.key)
            #expect(shown.deckID == card.deckID)
            if card.fretboardNote!.pitchClass.isNatural { #expect(shown == card) }
        }
    }

    @Test func presentIsDeterministicForASeed() {
        let options = FretboardOptions(noteSet: .all, accidentalSpelling: .mixed)
        let cards = fretboardCards(options)
        func run() -> [String] {
            var rng = SplitMix64(seed: 99)
            return cards.map { deck.present($0, options: .fretboard(options), using: &rng).fretboardNote!.spelling.displayName }
        }
        #expect(run() == run())
    }

    // MARK: Pattern penalty

    private func card(_ s: Int, _ letter: NoteLetter) -> Card {
        fretboardCards().first { $0.key == FretboardNotesDeck.itemKey(string: s, pitchClass: letter.pitchClass) }!
    }

    @Test func patternPenaltyRules() {
        let c = card(6, .a)
        #expect(deck.patternPenalty(candidate: c, recent: []) == 1)
        #expect(deck.patternPenalty(candidate: c, recent: [card(5, .c)][...]) == 1)
        #expect(deck.patternPenalty(candidate: c, recent: [card(6, .c)][...]) == 0.35)
        #expect(deck.patternPenalty(candidate: c, recent: [card(5, .a)][...]) == 0.35)
        #expect(abs(deck.patternPenalty(candidate: c, recent: [card(6, .c), card(6, .a)][...]) - 0.35 * 0.35 * 0.7) < 1e-12)
        #expect(deck.patternPenalty(candidate: c, recent: [card(6, .c), card(4, .d)][...]) == 0.7)
        #expect(deck.patternPenalty(candidate: c, recent: [card(6, .c), card(4, .d), card(3, .e)][...]) == 1)
    }

    // MARK: Display text

    @Test func promptTextMatchesSpec() {
        let p = card(6, .a).fretboardNote!
        #expect(deck.promptText(p, settings: .default) == "Play A (La) on string 6 (low E)")
        #expect(deck.promptText(p, settings: MusicDisplaySettings(naming: .letter, showStringHint: false)) == "Play A on string 6")
    }

    @Test func answerText() {
        #expect(FretboardNotesDeck.answerText(frets: [5]) == "Fret 5")
        #expect(FretboardNotesDeck.answerText(frets: [5, 17]) == "Fret 5 (also 17)")
        #expect(FretboardNotesDeck.answerText(frets: [0, 12, 24]) == "Open string (also 12, 24)")
        #expect(FretboardNotesDeck.answerText(frets: []) == "Not in range")
    }

    @Test func noIntroductionGatingAndRejectsForeignOptions() {
        #expect(fretboardCards().allSatisfy { deck.introductionRank(of: $0) == nil })
        #expect(deck.cards(options: .vocab(VocabOptions())).isEmpty)
        #expect(deck.defaultOptions == .fretboard(FretboardOptions()))
    }
}
