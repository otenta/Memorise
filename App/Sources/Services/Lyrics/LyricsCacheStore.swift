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
        if let file = LyricsCacheFile.decode(data) { return file }
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
        } catch {
            AppEnvironment.log.error("Lyrics cache write failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Adds machine glosses to an existing entry. Nothing is written for a track that has no entry.
    func mergeGlosses(_ glosses: [String: String], for spotifyID: String) {
        guard !glosses.isEmpty, var file = load(spotifyID) else { return }
        file.glosses.merge(glosses) { _, new in new }
        save(file)
    }

    /// Deletes every cached track (Settings → Lyrics → Clear lyrics cache).
    func clearAll() {
        memory = [:]
        guard let directory else { return }
        try? FileManager.default.removeItem(at: directory)
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
