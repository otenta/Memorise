import Foundation
import MemoriseCore
import Observation
import os

/// Shared app services, injected with `.environment(_:)`.
@MainActor @Observable
final class AppEnvironment {
    /// Bundled + generated + user decks; rebuilt by `reloadCatalog()`.
    private(set) var catalog: DeckCatalog
    /// Bundled vocab decks (loaded once at launch).
    @ObservationIgnored private let bundledVocab: [VocabDeck]
    /// User-created vocab decks (M4-8).
    private(set) var userDeckFiles: [VocabDeckFile] = []
    @ObservationIgnored let userDeckStore: UserDeckStore
    /// User deck files that couldn't be read this launch.
    private(set) var userDeckFailures: [String] = []
    @ObservationIgnored let store: any StatsStore
    @ObservationIgnored let audio: AudioSessionCoordinator
    @ObservationIgnored let speech: SpeechService
    @ObservationIgnored let notePlayer: NotePlayer
    @ObservationIgnored let deckUIs: DeckUIRegistry
    @ObservationIgnored let haptics = Haptics()
    @ObservationIgnored let configStore: SessionConfigStore
    let settings: AppSettings

    /// Bumped whenever stored data changes (session finished, reset) so screens reload.
    private(set) var dataVersion = 0
    /// Non-nil when progress is not being persisted this launch.
    private(set) var persistenceWarning: String?
    /// Problems found while loading bundled decks (shown on Home).
    let deckReport: DeckLoadReport

    nonisolated static let log = Logger(subsystem: "Memorise", category: "app")

    init(
        catalog: DeckCatalog,
        store: any StatsStore,
        settings: AppSettings = AppSettings(),
        configStore: SessionConfigStore = SessionConfigStore(),
        deckReport: DeckLoadReport = DeckLoadReport(),
        userDeckStore: UserDeckStore = UserDeckStore(directory: nil)
    ) {
        self.userDeckStore = userDeckStore
        self.catalog = catalog
        self.bundledVocab = catalog.vocabDecks
        self.store = store
        self.settings = settings
        let audio = AudioSessionCoordinator()
        self.audio = audio
        self.speech = SpeechService(audio: audio)
        self.notePlayer = NotePlayer(audio: audio)
        self.deckUIs = .builtIn
        notePlayer.volume = { [unowned settings] in Float(settings.noteVolume) }
        self.configStore = configStore
        self.deckReport = deckReport
    }

    /// Production wiring: bundled decks + SwiftData (bootstrapped off the main thread).
    static func live() -> AppEnvironment {
        #if DEBUG
        let formatErrors = PersistedFormatCheck.run()
        assert(formatErrors.isEmpty, "Persisted format changed:\n" + formatErrors.joined(separator: "\n"))
        let theoryErrors = TheoryCheck.run()
        assert(theoryErrors.isEmpty, "Theory check failed:\n" + theoryErrors.joined(separator: "\n"))
        #endif
        let (catalog, report) = DeckCatalog.builtIn()
        for f in report.loadFailures { log.error("Deck load failure: \(f, privacy: .public)") }
        for w in report.validationWarnings { log.error("Deck validation: \(w, privacy: .public)") }
        let store = DeferredStatsStore()
        let env = AppEnvironment(catalog: catalog, store: store, deckReport: report, userDeckStore: UserDeckStore())
        Task { [weak env] in await env?.loadUserDecks() }
        Task { [weak env] in
            let status = await store.status
            guard !status.persistent else { return }
            env?.persistenceWarning = status.error ?? "Storage unavailable"
        }
        return env
    }

    /// Preview wiring: in-memory store, optionally pre-filled.
    static func preview(store: InMemoryStatsStore = InMemoryStatsStore()) -> AppEnvironment {
        AppEnvironment(
            catalog: DeckCatalog.builtIn().catalog,
            store: store,
            settings: AppSettings(defaults: UserDefaults(suiteName: "preview") ?? .standard)
        )
    }

    func dataDidChange() { dataVersion &+= 1 }

    /// Rebuilds the catalog from bundled decks and the current user decks.
    /// Saved configs of deleted decks are simply never looked up again.
    func reloadCatalog() {
        catalog = DeckCatalog.assemble(bundledVocab: bundledVocab, userVocab: userDeckFiles.map(VocabDeck.init(file:)))
    }

    /// Replaces the user decks and rebuilds the catalog.
    func setUserDecks(_ files: [VocabDeckFile]) {
        userDeckFiles = files
        reloadCatalog()
    }

    /// Reads user decks from disk (launch).
    func loadUserDecks() async {
        let (files, failures) = await userDeckStore.loadAll()
        for f in failures { Self.log.error("User deck load failure: \(f, privacy: .public)") }
        userDeckFailures = failures
        setUserDecks(files)
    }

    /// User decks in display order (sorted by title).
    var userDecks: [VocabDeck] {
        let ids = Set(userDeckFiles.map(\.deckId))
        return catalog.vocabDecks.filter { ids.contains($0.id.raw) }
    }

    func userDeckFile(id: DeckID) -> VocabDeckFile? { userDeckFiles.first { $0.deckId == id.raw } }

    /// Saves (creates or replaces) a user deck, then rebuilds the catalog.
    func saveUserDeck(_ file: VocabDeckFile) async throws {
        try await userDeckStore.save(file)
        var files = userDeckFiles.filter { $0.deckId != file.deckId }
        files.append(file)
        files.sort { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        setUserDecks(files)
        dataDidChange()
    }

    /// "My AION words" (M4-9): created on first use.
    func ensureAionDeck() async throws -> DeckID {
        let id = DeckID(UserDecks.aionDeckID)
        if userDeckFile(id: id) == nil {
            try await saveUserDeck(UserDecks.newDeck(id: id.raw, title: "My AION words", subtitle: "Words from AION 2 screenshots"))
        }
        return id
    }

    /// Deletes a user deck file and its progress.
    func deleteUserDeck(id: DeckID) async throws {
        try await userDeckStore.delete(deckID: id.raw)
        try await store.reset(deck: id)
        setUserDecks(userDeckFiles.filter { $0.deckId != id.raw })
        dataDidChange()
    }

    /// UI provider for a deck.
    func deckUI(for deck: any Deck) -> any DeckUI { deckUIs.ui(for: deck) }

    /// Releases audio after a session (stops the synth, deactivates the session).
    func releaseAudio() {
        speech.stop()
        notePlayer.stop()
        audio.deactivate()
    }

    /// Last-used (or default) configuration for a deck, with app defaults applied.
    func initialConfig(for deck: any Deck) -> SessionConfig {
        let ui = deckUI(for: deck)
        let modes = ui.supportedInputModes(deck: deck)
        if var saved = configStore.load(for: deck.id), saved.recoveredFields.isEmpty,
           saved.options.sameCase(as: deck.defaultOptions) {
            saved.options = ui.sanitize(saved.options, deck: deck)
            if !speech.hasKoreanVoice, case let .vocab(o) = saved.options { saved.options = .vocab(o.withoutListening()) }
            if !modes.contains(saved.inputMode) { saved.inputMode = modes.first ?? .touch }
            return saved
        }
        var config = SessionConfig.default(for: deck)
        config.inputMode = modes.first ?? .touch
        if case var .fretboard(o) = config.options {
            o.fretRange = 0...settings.defaultMaxFret
            config.options = .fretboard(o)
        }
        return config
    }
}
