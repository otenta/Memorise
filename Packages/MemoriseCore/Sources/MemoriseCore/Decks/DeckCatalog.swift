import Foundation

/// Problems found while loading bundled decks.
public struct DeckLoadReport: Sendable, Hashable {
    /// Files that couldn't be read or decoded (their decks are missing).
    public var loadFailures: [String] = []
    /// Validator errors (decks are loaded, but stats may be mixed for affected entries).
    public var validationWarnings: [String] = []

    public init(loadFailures: [String] = [], validationWarnings: [String] = []) {
        self.loadFailures = loadFailures
        self.validationWarnings = validationWarnings
    }

    public var isEmpty: Bool { loadFailures.isEmpty && validationWarnings.isEmpty }
}

/// Every deck available this launch: music decks, generated Korean decks, bundled vocab, user decks.
public struct DeckCatalog: Sendable {
    public let decks: [any Deck]
    private let index: [DeckID: Int]

    public init(decks: [any Deck]) {
        self.decks = decks
        self.index = Dictionary(decks.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    public func deck(id: DeckID) -> (any Deck)? {
        index[id].map { decks[$0] }
    }

    public func decks(for subject: Subject) -> [any Deck] {
        decks.filter { $0.subject == subject }
    }

    /// Every vocab-file deck (bundled and user), in catalog order.
    public var vocabDecks: [VocabDeck] { decks.compactMap { $0 as? VocabDeck } }

    /// Builds the catalog from loaded vocab decks. Generated Korean decks draw on every vocab deck
    /// (bundled + user), so call this again (`AppEnvironment.reloadCatalog()`) when user decks change.
    public static func assemble(bundledVocab: [VocabDeck], userVocab: [VocabDeck] = []) -> DeckCatalog {
        let vocab = bundledVocab + userVocab
        let korean = koreanDisplayOrder(BuiltInDecks.koreanGeneratedDecks(vocab: vocab) + vocab)
        return DeckCatalog(decks: BuiltInDecks.musicDecks + korean)
    }

    /// PLAN_M4 M4-10: Hangul Reading, Core 1…N, Particles, Conjugation, Patterns, other bundled decks
    /// (K-media), AION 2, then user decks (title order kept). Stable within each slot.
    static func koreanDisplayOrder(_ decks: [any Deck]) -> [any Deck] {
        func slot(_ d: any Deck) -> (Int, Int) {
            let raw = d.id.raw
            if raw == HangulReadingDeck.deckID.raw { return (0, 0) }
            if raw.hasPrefix(ConjugationDeck.corePrefix) { return (1, ConjugationDeck.coreNumber(d.id)) }
            if raw == ParticlesDeck.deckID.raw { return (2, 0) }
            if raw == ConjugationDeck.deckID.raw { return (3, 0) }
            if raw == "ko.patterns" { return (4, 0) }
            if UserDecks.isUserDeckID(d.id) { return (7, 0) }
            if raw == "ko.aion2" { return (6, 0) }
            return (5, 0)
        }
        return decks.enumerated()
            .sorted { (slot($0.element).0, slot($0.element).1, $0.offset) < (slot($1.element).0, slot($1.element).1, $1.offset) }
            .map(\.element)
    }

    /// Bundled vocab files in display order.
    /// M5 K1: `"ko_media"` goes before `"ko_aion2"` once K2 adds `ko_media.json`; until then a missing file
    /// would show the "couldn't be loaded" row, so it stays out of the list.
    public static let bundledVocabFiles = [
        "ko_core_1", "ko_core_2", "ko_core_3", "ko_core_4", "ko_core_5", "ko_patterns",
        // "ko_media", // M5 K2
        "ko_aion2",
    ]

    /// Fretboard Notes + every bundled vocab deck that loads.
    ///
    /// Each file loads independently: a failing file is skipped and reported in `issues`.
    /// Validation runs in all configurations; its errors are reported but the deck is still used.
    public static func builtIn() -> (catalog: DeckCatalog, report: DeckLoadReport) {
        builtIn(files: bundledVocabFiles)
    }

    static func builtIn(files names: [String]) -> (catalog: DeckCatalog, report: DeckLoadReport) {
        var report = DeckLoadReport()
        var files: [VocabDeckFile] = []
        for name in names {
            do {
                files.append(try loadBundledVocabFile(named: name))
            } catch {
                report.loadFailures.append("\(name): \(error.localizedDescription)")
            }
        }
        report.validationWarnings = DeckValidator.validate(files) + ChordShapeLibrary.shared.warnings
        #if DEBUG
        assert(report.validationWarnings.isEmpty, "Invalid bundled decks:\n" + report.validationWarnings.joined(separator: "\n"))
        #endif
        return (assemble(bundledVocab: files.map(VocabDeck.init(file:))), report)
    }

    /// Loads `Resources/Decks/<name>.json` from the package bundle.
    public static func loadBundledVocabFile(named name: String) throws -> VocabDeckFile {
        guard let url = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Decks") else {
            throw CocoaError(.fileNoSuchFile, userInfo: [NSFilePathErrorKey: "Decks/\(name).json"])
        }
        return try JSONDecoder().decode(VocabDeckFile.self, from: Data(contentsOf: url))
    }
}
