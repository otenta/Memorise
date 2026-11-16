import Foundation
import MemoriseCore
import Observation
import os

/// Shared app services, injected with `.environment(_:)`.
@MainActor @Observable
final class AppEnvironment {
    @ObservationIgnored let catalog: DeckCatalog
    @ObservationIgnored let store: any StatsStore
    @ObservationIgnored let speech = SpeechService()
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
        deckReport: DeckLoadReport = DeckLoadReport()
    ) {
        self.catalog = catalog
        self.store = store
        self.settings = settings
        self.configStore = configStore
        self.deckReport = deckReport
    }

    /// Production wiring: bundled decks + SwiftData (bootstrapped off the main thread).
    static func live() -> AppEnvironment {
        #if DEBUG
        let formatErrors = PersistedFormatCheck.run()
        assert(formatErrors.isEmpty, "Persisted format changed:\n" + formatErrors.joined(separator: "\n"))
        #endif
        let (catalog, report) = DeckCatalog.builtIn()
        for f in report.loadFailures { log.error("Deck load failure: \(f, privacy: .public)") }
        for w in report.validationWarnings { log.error("Deck validation: \(w, privacy: .public)") }
        let store = DeferredStatsStore()
        let env = AppEnvironment(catalog: catalog, store: store, deckReport: report)
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

    /// Last-used (or default) configuration for a deck, with app defaults applied.
    func initialConfig(for deck: any Deck) -> SessionConfig {
        if var saved = configStore.load(for: deck.id), saved.recoveredFields.isEmpty,
           saved.options == saved.options.normalized(for: deck) {
            // Drop tag filters the deck no longer has.
            if case let .vocab(o) = saved.options, let vocab = deck as? VocabDeck {
                saved.options = .vocab(o.sanitized(allTags: vocab.allTags))
            }
            return saved
        }
        var config = SessionConfig.default(for: deck)
        if case var .fretboard(o) = config.options {
            o.fretRange = 0...settings.defaultMaxFret
            config.options = .fretboard(o)
        }
        return config
    }
}

private extension DeckOptions {
    /// Options of the right kind for the deck (guards against stale saved configs).
    func normalized(for deck: any Deck) -> DeckOptions {
        switch (self, deck.defaultOptions) {
        case (.fretboard, .fretboard), (.vocab, .vocab): self
        default: deck.defaultOptions
        }
    }
}
