import Foundation
import MemoriseCore

/// "My snippet" notes on disk: `Application Support/personal_snippets.json` (PLAN_M5 K4).
/// No SwiftData schema change. Every write is atomic. Nothing leaves the device except through Export.
actor PersonalSnippetStore {
    private let fileURL: URL?
    private var cache: [String: PersonalSnippet]?
    /// Set when an unreadable file couldn't be moved aside: writes are refused so it is never overwritten.
    private var writesBlocked = false

    struct WritesBlocked: LocalizedError {
        var errorDescription: String? { "Your snippets file couldn't be read, so it isn't being changed." }
    }

    /// `fileURL == nil` keeps snippets in memory only (previews).
    init(fileURL: URL? = PersonalSnippetStore.defaultFileURL) {
        self.fileURL = fileURL
    }

    static var defaultFileURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("personal_snippets.json")
    }

    /// All snippets keyed by entry id. An unreadable file is moved aside (never overwritten) and reported.
    func loadAll() -> (snippets: [String: PersonalSnippet], failure: String?) {
        if let cache { return (cache, nil) }
        guard let fileURL, FileManager.default.fileExists(atPath: fileURL.path) else {
            cache = [:]
            return ([:], nil)
        }
        do {
            let file = try PersonalSnippetFile.decoder().decode(PersonalSnippetFile.self, from: Data(contentsOf: fileURL))
            cache = file.snippets
            return (file.snippets, nil)
        } catch {
            let aside = moveAside(fileURL)
            writesBlocked = aside == nil
            cache = [:]
            return ([:], "personal_snippets.json unreadable (\(error.localizedDescription)); kept as \(aside ?? "?")")
        }
    }

    /// Saves the snippet for `entryID`; an empty text deletes it. Returns the stored value (`nil` = deleted).
    @discardableResult
    func save(entryID: String, text: String, source: String?, now: Date = Date()) throws -> PersonalSnippet? {
        let snippet = PersonalSnippet(text: text, source: source, updatedAt: now)
        var all = loadAll().snippets
        all[entryID] = snippet.isEmpty ? nil : snippet
        try write(all)
        return all[entryID]
    }

    func delete(entryID: String) throws {
        var all = loadAll().snippets
        guard all.removeValue(forKey: entryID) != nil else { return }
        try write(all)
    }

    /// Removes every snippet (reset-all, when the user also chose to delete snippets).
    func deleteAll() throws {
        if writesBlocked { throw WritesBlocked() }
        cache = [:]
        guard let fileURL, FileManager.default.fileExists(atPath: fileURL.path) else { return }
        try FileManager.default.removeItem(at: fileURL)
    }

    private func write(_ all: [String: PersonalSnippet]) throws {
        if writesBlocked { throw WritesBlocked() }
        if let fileURL {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try PersonalSnippetFile.encoder().encode(PersonalSnippetFile(snippets: all)).write(to: fileURL, options: .atomic)
        }
        cache = all
    }

    /// Renames an unreadable file to `personal_snippets.unreadable-<timestamp>.json`; returns the new name.
    private func moveAside(_ url: URL) -> String? {
        let stamp = Int(Date().timeIntervalSince1970)
        let target = url.deletingLastPathComponent().appendingPathComponent("personal_snippets.unreadable-\(stamp).json")
        do {
            try FileManager.default.moveItem(at: url, to: target)
            return target.lastPathComponent
        } catch {
            return nil
        }
    }
}
