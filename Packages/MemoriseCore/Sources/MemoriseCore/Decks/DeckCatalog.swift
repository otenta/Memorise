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

/// All built-in decks.
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

    /// Bundled vocab files in display order.
    public static let bundledVocabFiles = ["ko_core_1", "ko_aion2"]

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
        report.validationWarnings = DeckValidator.validate(files)
        #if DEBUG
        assert(report.validationWarnings.isEmpty, "Invalid bundled decks:\n" + report.validationWarnings.joined(separator: "\n"))
        #endif
        return (DeckCatalog(decks: [FretboardNotesDeck()] + files.map(VocabDeck.init(file:))), report)
    }

    /// Loads `Resources/Decks/<name>.json` from the package bundle.
    public static func loadBundledVocabFile(named name: String) throws -> VocabDeckFile {
        guard let url = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Decks") else {
            throw CocoaError(.fileNoSuchFile, userInfo: [NSFilePathErrorKey: "Decks/\(name).json"])
        }
        return try JSONDecoder().decode(VocabDeckFile.self, from: Data(contentsOf: url))
    }
}
