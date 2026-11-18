import Foundation
import MemoriseCore

/// Lyrics cache on disk: one JSON file per track in `Application Support/LyricsCache/` (PLAN_M6 §4.7).
/// Writes are atomic. The folder is excluded from device backups and from the data export (copyright).
actor LyricsCacheStore {
    private let directory: URL?
    /// Used only when `directory` is nil (previews).
    private var memory: [String: LyricsCacheFile] = [:]

    /// `directory == nil` keeps the cache in memory only (previews).
    init(directory: URL? = LyricsCacheStore.defaultDirectory) {
        self.directory = directory
    }

    static var defaultDirectory: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("LyricsCache", isDirectory: true)
    }

    /// The cached entry, or `nil` when there is none. An unreadable file is deleted so the track is refetched.
    func load(_ spotifyID: String) -> LyricsCacheFile? {
        guard let url = fileURL(spotifyID) else { return memory[spotifyID] }
        guard let data = try? Data(contentsOf: url) else { return nil }
        if let file = LyricsCacheFile.decode(data) {
            // A hit counts as a use, so pruning removes the least recently opened tracks.
            try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: url.path)
            return file
        }
        try? FileManager.default.removeItem(at: url)
        return nil
    }

    func save(_ file: LyricsCacheFile) {
        let id = file.track.spotifyID
        guard let url = fileURL(id), let directory else { memory[id] = file; return }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            Self.excludeFromBackup(directory)
            try file.encoded().write(to: url, options: .atomic)
            prune(directory)
        } catch {
            AppEnvironment.log.error("Lyrics cache write failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Adds machine glosses (words and whole lines) to an existing entry with one load and one save.
    /// Nothing is written when both are empty, or for a track that has no entry.
    func mergeGlosses(words: [String: String], lines: [String: String], for spotifyID: String) {
        guard !words.isEmpty || !lines.isEmpty, var file = load(spotifyID) else { return }
        file.glosses.merge(words) { _, new in new }
        file.lineGlosses.merge(lines) { _, new in new }
        save(file)
    }

    /// Deletes every cached track (Settings → Lyrics → Clear lyrics cache).
    func clearAll() {
        memory = [:]
        guard let directory else { return }
        try? FileManager.default.removeItem(at: directory)
    }

    /// Keeps at most `LyricsConstants.cacheMaxEntries` files, deleting the oldest by modification date.
    private func prune(_ directory: URL) {
        let keys: [URLResourceKey] = [.contentModificationDateKey]
        guard let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: keys),
              files.count > LyricsConstants.cacheMaxEntries else { return }
        let dated = files.map { ($0, (try? $0.resourceValues(forKeys: Set(keys)).contentModificationDate) ?? .distantPast) }
        for (url, _) in dated.sorted(by: { $0.1 < $1.1 }).prefix(files.count - LyricsConstants.cacheMaxEntries) {
            try? FileManager.default.removeItem(at: url)
        }
    }

    private func fileURL(_ spotifyID: String) -> URL? {
        guard let directory else { return nil }
        // Spotify ids are base-62; anything else must never reach a path.
        let safe = String(spotifyID.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) && $0.isASCII })
        guard !safe.isEmpty else { return nil }
        return directory.appendingPathComponent("\(safe).json")
    }

    private static func excludeFromBackup(_ url: URL) {
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var u = url
        try? u.setResourceValues(values)
    }
}
