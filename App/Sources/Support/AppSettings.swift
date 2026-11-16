import Foundation
import MemoriseCore
import Observation

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

    @ObservationIgnored private let defaults: UserDefaults

    private enum Key: String {
        case noteNaming, solfegeVariant, leftHanded, highEOnTop, defaultMaxFret, showStringHint
        case autoPlayPronunciation, speechRate, showRomanization, koreanVoiceHintShown
        case tapAnywhereForOK, showTimer, hapticsEnabled
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        func bool(_ k: Key, _ d: Bool) -> Bool { defaults.object(forKey: k.rawValue) as? Bool ?? d }
        noteNaming = defaults.string(forKey: Key.noteNaming.rawValue).flatMap(NoteNaming.init) ?? .both
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
