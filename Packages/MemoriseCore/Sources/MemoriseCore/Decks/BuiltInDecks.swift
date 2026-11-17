/// The single closed table of built-in deck ids in core. Every new deck adds one row.
public enum BuiltInDecks {
    /// Default options per deck id; any `ko.` deck is a vocab deck.
    public static func defaultOptions(for id: DeckID) -> DeckOptions {
        switch id {
        case FretboardNotesDeck.deckID, FretboardNamesDeck.deckID, FindAllDeck.deckID:
            return .fretboard(FretboardOptions())
        case IntervalsDeck.deckID:
            return .intervals(IntervalOptions())
        case EarIntervalsDeck.deckID:
            return .earIntervals(EarIntervalOptions())
        case ChordsPlayDeck.deckID, ChordsNameDeck.deckID:
            return .chords(ChordOptions())
        case TriadsDeck.deckID:
            return .triads(TriadOptions())
        case ArpeggiosDeck.deckID:
            return .arpeggios(ArpeggioOptions())
        case ScalesDeck.deckID:
            return .scales(ScaleOptions())
        case KeySignaturesDeck.deckID:
            return .keySignatures(KeySigOptions())
        case DiatonicDeck.deckID:
            return .diatonic(DiatonicOptions())
        case ProgressionsDeck.deckID:
            return .progressions(ProgressionOptions())
        case CircleOfFifthsDeck.deckID:
            return .circle(CircleOptions())
        case HangulReadingDeck.deckID:
            return .hangulReading(HangulReadingOptions())
        case ParticlesDeck.deckID:
            return .particles(ParticleOptions())
        case ConjugationDeck.deckID:
            return .conjugation(ConjugationOptions())
        default:
            return id.raw.hasPrefix("ko.") || UserDecks.isUserDeckID(id) ? .vocab(VocabOptions()) : .fretboard(FretboardOptions())
        }
    }

    /// Generated music decks in display order (grouped per PLAN_M3 §3.4).
    public static let musicDecks: [any Deck] = [
        // Fretboard
        FretboardNotesDeck(), FretboardNamesDeck(), FindAllDeck(), IntervalsDeck(),
        // Ear
        EarIntervalsDeck(),
        // Chords & shapes
        ChordsPlayDeck(), ChordsNameDeck(), TriadsDeck(), ArpeggiosDeck(), ProgressionsDeck(),
        // Scales
        ScalesDeck(),
        // Theory
        KeySignaturesDeck(), DiatonicDeck(), CircleOfFifthsDeck(),
    ]
}

public extension BuiltInDecks {
    /// Korean decks generated from the vocab pool (Hangul reading, particles, conjugation), in display order.
    static func koreanGeneratedDecks(vocab: [VocabDeck]) -> [any Deck] {
        [HangulReadingDeck(vocab: vocab), ParticlesDeck(vocab: vocab), ConjugationDeck(vocab: vocab)]
    }
}

extension FretboardNotesDeck { public var group: String { DeckGroup.fretboard } }
extension FretboardNamesDeck { public var group: String { DeckGroup.fretboard } }
extension FindAllDeck { public var group: String { DeckGroup.fretboard } }
extension IntervalsDeck { public var group: String { DeckGroup.fretboard } }
extension EarIntervalsDeck { public var group: String { DeckGroup.ear } }
