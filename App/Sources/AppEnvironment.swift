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
    /// User decks deleted before the launch load finished (R4-10): a stale disk read mustn't revive them.
    @ObservationIgnored private var userDecksDeletedBeforeLoad = Set<String>()
    @ObservationIgnored private var userDecksLoaded = false
    @ObservationIgnored let userDeckStore: UserDeckStore
    /// User deck files that couldn't be read this launch.
    private(set) var userDeckFailures: [String] = []
    /// "My snippet" notes keyed by vocab entry id (M5 K4). On-device only.
    private(set) var personalSnippets: [String: PersonalSnippet] = [:]
    @ObservationIgnored let snippetStore: PersonalSnippetStore
    /// Snippet deletes made before the launch load finished (R5-6a): a stale disk read mustn't revive them.
    @ObservationIgnored private var snippetsLoaded = false
    @ObservationIgnored private var snippetsDeletedBeforeLoad = Set<String>()
    @ObservationIgnored private var snippetsDeleteAllBeforeLoad = false
    /// Non-nil when the snippets file couldn't be read this launch.
    private(set) var snippetLoadFailure: String?
    @ObservationIgnored let store: any StatsStore
    @ObservationIgnored let audio: AudioSessionCoordinator
    @ObservationIgnored let speech: SpeechService
    @ObservationIgnored let notePlayer: NotePlayer
    @ObservationIgnored let deckUIs: DeckUIRegistry
    @ObservationIgnored let haptics = Haptics()
    @ObservationIgnored let configStore: SessionConfigStore
    let settings: AppSettings
    /// Spotify sign-in and Web API for the Lyrics tab (M6).
    let spotify: SpotifyClient
    /// Lyrics provider chain and on-device cache (M6).
    let lyrics: LyricsService
    /// Word meanings for the lyrics bubble (M6).
    let glosses: GlossService

    /// Card-pool sizes by deck and options (R5-2): Home and Setup only need the count, and building
    /// every pool on each `dataVersion` bump was ~90 ms of main-thread work. Cleared by `reloadCatalog()`.
    @ObservationIgnored private var cardKeysCache: [CardCountKey: [ItemKey]] = [:]
    private struct CardCountKey: Hashable {
        let deck: DeckID
        let options: DeckOptions
    }

    /// The previous session's final writes (`SessionRecorder.close()`). A new session awaits it before reading stats,
    /// so it never starts from a store that is still being written (R7-2).
    @ObservationIgnored var pendingFlush: Task<Void, Never>?

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
        userDeckStore: UserDeckStore = UserDeckStore(directory: nil),
        snippetStore: PersonalSnippetStore = PersonalSnippetStore(fileURL: nil),
        spotify: SpotifyClient = SpotifyClient(),
        lyrics: LyricsService = LyricsService()
    ) {
        self.spotify = spotify
        self.lyrics = lyrics
        self.glosses = GlossService(catalog: catalog, cache: lyrics.cache)
        self.userDeckStore = userDeckStore
        self.snippetStore = snippetStore
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
        #if DEBUG
        // R7-F7: content overlap across Korean decks (debug report only; input for C2).
        for w in report.overlapWarnings { log.debug("Deck overlap: \(w, privacy: .public)") }
        #endif
        let store = DeferredStatsStore()
        let env = AppEnvironment(
            catalog: catalog, store: store, deckReport: report,
            userDeckStore: UserDeckStore(), snippetStore: PersonalSnippetStore()
        )
        Task { [weak env] in await env?.loadUserDecks() }
        Task { [weak env] in await env?.loadPersonalSnippets() }
        Task { [weak env] in await env?.spotify.restore() }
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
            settings: AppSettings(defaults: UserDefaults(suiteName: "preview") ?? .standard),
            // Previews never touch the Keychain, the network or the lyrics cache on disk.
            spotify: SpotifyClient(
                auth: SpotifyAuth(clientID: "preview", http: OfflineHTTPClient(), secrets: InMemorySecretStore()),
                http: OfflineHTTPClient()),
            lyrics: LyricsService(http: OfflineHTTPClient(), cache: LyricsCacheStore(directory: nil), geniusToken: "")
        )
    }

    func dataDidChange() { dataVersion &+= 1 }

    /// Rebuilds the catalog from bundled decks and the current user decks.
    /// Saved configs of deleted decks are simply never looked up again.
    func reloadCatalog() {
        cardKeysCache = [:]
        catalog = DeckCatalog.assemble(bundledVocab: bundledVocab, userVocab: userDeckFiles.map(VocabDeck.init(file:)))
        glosses.catalogDidChange(catalog)
    }

    /// Replaces the user decks and rebuilds the catalog.
    func setUserDecks(_ files: [VocabDeckFile]) {
        userDeckFiles = files
        reloadCatalog()
    }

    /// Reads user decks from disk (launch).
    ///
    /// Merges by `deckId` instead of replacing (R4-10): a deck saved while the load was in flight
    /// is already in memory and newer than (or equal to) what was read, so memory wins.
    func loadUserDecks() async {
        let (files, failures) = await userDeckStore.loadAll()
        for f in failures { Self.log.error("User deck load failure: \(f, privacy: .public)") }
        userDeckFailures = failures
        let inMemory = Set(userDeckFiles.map(\.deckId))
        var merged = userDeckFiles
        merged += files.filter { !inMemory.contains($0.deckId) && !userDecksDeletedBeforeLoad.contains($0.deckId) }
        merged.sort { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        userDecksLoaded = true
        userDecksDeletedBeforeLoad = []
        setUserDecks(merged)
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
    /// Stats first, then the file (R4-10): if either step throws, the deck keeps its file and stays
    /// in the catalog, so it can be deleted again — never a catalog entry with no file behind it.
    func deleteUserDeck(id: DeckID) async throws {
        try await store.reset(deck: id)
        defer { dataDidChange() }
        try await userDeckStore.delete(deckID: id.raw)
        if !userDecksLoaded { userDecksDeletedBeforeLoad.insert(id.raw) }
        setUserDecks(userDeckFiles.filter { $0.deckId != id.raw })
    }

    // MARK: Personal snippets (M5 K4)

    /// Reads snippets from disk (launch).
    func loadPersonalSnippets() async {
        let (snippets, failure) = await snippetStore.loadAll()
        if let failure { Self.log.error("Snippet load failure: \(failure, privacy: .public)") }
        snippetLoadFailure = failure
        // Same launch race as user decks: snippets saved meanwhile are newer, so memory wins, and
        // snippets deleted meanwhile stay deleted.
        var fromDisk = snippetsDeleteAllBeforeLoad ? [:] : snippets
        for id in snippetsDeletedBeforeLoad { fromDisk[id] = nil }
        personalSnippets = fromDisk.merging(personalSnippets) { _, inMemory in inMemory }
        snippetsLoaded = true
        snippetsDeletedBeforeLoad = []
        snippetsDeleteAllBeforeLoad = false
    }

    func personalSnippet(for entryID: String) -> PersonalSnippet? { personalSnippets[entryID] }

    /// Saves the snippet for an entry; an empty (after trimming) text deletes it.
    func savePersonalSnippet(entryID: String, text: String, source: String?) async throws {
        let saved = try await snippetStore.save(entryID: entryID, text: text, source: source)
        personalSnippets[entryID] = saved
        // A later save wins over an earlier delete; an empty save is itself a delete.
        if !snippetsLoaded {
            if saved == nil { snippetsDeletedBeforeLoad.insert(entryID) } else { snippetsDeletedBeforeLoad.remove(entryID) }
        }
    }

    func deletePersonalSnippet(entryID: String) async throws {
        try await snippetStore.delete(entryID: entryID)
        personalSnippets[entryID] = nil
        if !snippetsLoaded { snippetsDeletedBeforeLoad.insert(entryID) }
    }

    /// Reset-all, when the user also chose "Also delete my snippets?".
    func deleteAllPersonalSnippets() async throws {
        try await snippetStore.deleteAll()
        personalSnippets = [:]
        if !snippetsLoaded {
            snippetsDeleteAllBeforeLoad = true
            snippetsDeletedBeforeLoad = []
        }
    }

    /// Keys of the cards `deck` yields for `options`, computed once per (deck, options) until the catalog reloads.
    func cardKeys(for deck: any Deck, options: DeckOptions) -> [ItemKey] {
        let key = CardCountKey(deck: deck.id, options: options)
        if let cached = cardKeysCache[key] { return cached }
        let keys = deck.cards(options: options).map(\.key)
        cardKeysCache[key] = keys
        return keys
    }

    /// Number of cards `deck` yields for `options` (same cache as `cardKeys`).
    func cardCount(for deck: any Deck, options: DeckOptions) -> Int {
        cardKeys(for: deck, options: options).count
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
            saved.micTimeoutSeconds = SessionConfig.nearestMicTimeoutPreset(saved.micTimeoutSeconds)
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
