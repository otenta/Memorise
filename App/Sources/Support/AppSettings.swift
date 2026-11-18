import Foundation
import MemoriseCore
import Observation

/// What M3 fretboard dots show.
enum DotLabels: String, CaseIterable {
    case notes, degrees
}

/// User preferences, persisted to `UserDefaults` on every change.
@MainActor @Observable
final class AppSettings {
    // Music
    var noteNaming: NoteNaming { didSet { store(noteNaming.rawValue, .noteNaming) } }
    var solfegeVariant: SolfegeVariant { didSet { store(solfegeVariant.rawValue, .solfegeVariant) } }
    var leftHanded: Bool { didSet { store(leftHanded, .leftHanded) } }
    /// `true` = high E on top (tab orientation).
    var highEOnTop: Bool { didSet { store(highEOnTop, .highEOnTop) } }
    var defaultMaxFret: Int { didSet { store(defaultMaxFret, .defaultMaxFret) } }
    var showStringHint: Bool { didSet { store(showStringHint, .showStringHint) } }
    var playNoteOnReveal: Bool { didSet { store(playNoteOnReveal, .playNoteOnReveal) } }
    /// Synth output gain 0…1.
    var noteVolume: Double { didSet { store(noteVolume, .noteVolume) } }
    /// Scales/arpeggios/triads dot labels.
    var dotLabels: DotLabels { didSet { store(dotLabels.rawValue, .dotLabels) } }
    /// "A-shape barre" hint on Play the Chord prompts.
    var showShapeHint: Bool { didSet { store(showShapeHint, .showShapeHint) } }
    /// Microphone answers: say "Correct" / "Try again" (R7-F3). Banners and haptics always run.
    var spokenMicFeedback: Bool { didSet { store(spokenMicFeedback, .spokenMicFeedback) } }

    // Korean
    var autoPlayPronunciation: Bool { didSet { store(autoPlayPronunciation, .autoPlayPronunciation) } }
    /// `AVSpeechUtterance.rate` (0…1).
    var speechRate: Double { didSet { store(speechRate, .speechRate) } }
    var showRomanization: Bool { didSet { store(showRomanization, .showRomanization) } }
    var koreanVoiceHintShown: Bool { didSet { store(koreanVoiceHintShown, .koreanVoiceHintShown) } }

    // Session
    var tapAnywhereForOK: Bool { didSet { store(tapAnywhereForOK, .tapAnywhereForOK) } }
    var showTimer: Bool { didSet { store(showTimer, .showTimer) } }
    var hapticsEnabled: Bool { didSet { store(hapticsEnabled, .hapticsEnabled) } }
    /// Typed/choice answers: move on after 0.8 s when exactly correct.
    var autoAdvanceOnCorrect: Bool { didSet { store(autoAdvanceOnCorrect, .autoAdvanceOnCorrect) } }
    /// M6: the deck lyric words were last saved to (offered first next time). `nil` until the first save.
    var lastLyricsDeckID: String? {
        didSet {
            if let id = lastLyricsDeckID { store(id, .lastLyricsDeckID) } else { defaults.removeObject(forKey: Key.lastLyricsDeckID.rawValue) }
        }
    }

    @ObservationIgnored private let defaults: UserDefaults

    private enum Key: String {
        case noteNaming, solfegeVariant, leftHanded, highEOnTop, defaultMaxFret, showStringHint
        case playNoteOnReveal, noteVolume, dotLabels, showShapeHint, spokenMicFeedback
        case autoPlayPronunciation, speechRate, showRomanization, koreanVoiceHintShown
        case tapAnywhereForOK, showTimer, hapticsEnabled, autoAdvanceOnCorrect, lastLyricsDeckID
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        func bool(_ k: Key, _ d: Bool) -> Bool { defaults.object(forKey: k.rawValue) as? Bool ?? d }
        noteNaming = defaults.string(forKey: Key.noteNaming.rawValue).flatMap(NoteNaming.init) ?? .both
        playNoteOnReveal = bool(.playNoteOnReveal, false)
        noteVolume = defaults.object(forKey: Key.noteVolume.rawValue) as? Double ?? 0.8
        dotLabels = defaults.string(forKey: Key.dotLabels.rawValue).flatMap(DotLabels.init) ?? .notes
        showShapeHint = bool(.showShapeHint, true)
        spokenMicFeedback = bool(.spokenMicFeedback, true)
        solfegeVariant = defaults.string(forKey: Key.solfegeVariant.rawValue).flatMap(SolfegeVariant.init) ?? .si
        leftHanded = bool(.leftHanded, false)
        highEOnTop = bool(.highEOnTop, true)
        defaultMaxFret = defaults.object(forKey: Key.defaultMaxFret.rawValue) as? Int ?? 12
        showStringHint = bool(.showStringHint, true)
        autoPlayPronunciation = bool(.autoPlayPronunciation, true)
        speechRate = defaults.object(forKey: Key.speechRate.rawValue) as? Double ?? 0.45
        showRomanization = bool(.showRomanization, true)
        koreanVoiceHintShown = bool(.koreanVoiceHintShown, false)
        tapAnywhereForOK = bool(.tapAnywhereForOK, true)
        showTimer = bool(.showTimer, false)
        hapticsEnabled = bool(.hapticsEnabled, true)
        autoAdvanceOnCorrect = bool(.autoAdvanceOnCorrect, true)
        lastLyricsDeckID = defaults.string(forKey: Key.lastLyricsDeckID.rawValue)
    }

    private func store(_ value: Any, _ key: Key) { defaults.set(value, forKey: key.rawValue) }

    /// Core-facing subset used by formatting functions.
    var musicDisplay: MusicDisplaySettings {
        MusicDisplaySettings(naming: noteNaming, solfegeVariant: solfegeVariant, showStringHint: showStringHint)
    }
}

/// Remembers the last-used session configuration per deck (JSON in `UserDefaults`).
@MainActor
struct SessionConfigStore {
    let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    private func key(_ deck: DeckID) -> String { "lastConfig.\(deck.raw)" }

    func load(for deck: DeckID) -> SessionConfig? {
        defaults.data(forKey: key(deck)).flatMap { try? JSONDecoder().decode(SessionConfig.self, from: $0) }
    }

    func save(_ config: SessionConfig) {
        if let data = try? JSONEncoder().encode(config) { defaults.set(data, forKey: key(config.deckID)) }
    }
}
