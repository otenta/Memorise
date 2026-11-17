import Foundation
import MemoriseCore

/// User-created decks on disk: `Application Support/UserDecks/<deckId>.json` (PLAN_M4 M4-8).
/// Same `VocabDeckFile` format as the bundled decks, plus `nextEntryNumber`.
actor UserDeckStore {
    private let directory: URL?

    /// `directory == nil` keeps nothing on disk (previews).
    init(directory: URL? = UserDeckStore.defaultDirectory) {
        self.directory = directory
    }

    static var defaultDirectory: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("UserDecks", isDirectory: true)
    }

    /// Every readable deck file, sorted by title; unreadable files are reported, not deleted.
    func loadAll() -> (decks: [VocabDeckFile], failures: [String]) {
        guard let directory,
              let urls = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        else { return ([], []) }
        var decks: [VocabDeckFile] = []
        var failures: [String] = []
        let decoder = JSONDecoder()
        for url in urls where url.pathExtension == "json" {
            do {
                let file = try decoder.decode(VocabDeckFile.self, from: Data(contentsOf: url))
                guard UserDecks.isUserDeckID(DeckID(file.deckId)) else {
                    failures.append("\(url.lastPathComponent): not a user deck id")
                    continue
                }
                decks.append(file)
            } catch {
                failures.append("\(url.lastPathComponent): \(error.localizedDescription)")
            }
        }
        decks.sort { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        return (decks, failures)
    }

    func save(_ file: VocabDeckFile) throws {
        guard let directory else { return }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(file).write(to: url(for: file.deckId), options: .atomic)
    }

    func delete(deckID: String) throws {
        guard directory != nil else { return }
        let url = url(for: deckID)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }

    private func url(for deckID: String) -> URL {
        directory!.appendingPathComponent("\(deckID).json")
    }
}
