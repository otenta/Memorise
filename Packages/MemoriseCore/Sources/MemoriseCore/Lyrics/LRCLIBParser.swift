import Foundation

/// One LRCLIB record (`/api/get` returns one, `/api/search` an array).
public struct LRCLIBRecord: Hashable, Sendable, Decodable {
    public var trackName: String
    public var artistName: String
    public var albumName: String
    /// Seconds.
    public var duration: Double?
    public var instrumental: Bool
    public var plainLyrics: String?
    public var syncedLyrics: String?

    private enum CodingKeys: String, CodingKey {
        case trackName, artistName, albumName, duration, instrumental, plainLyrics, syncedLyrics
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        trackName = (try? c.decodeIfPresent(String.self, forKey: .trackName)) ?? ""
        artistName = (try? c.decodeIfPresent(String.self, forKey: .artistName)) ?? ""
        albumName = (try? c.decodeIfPresent(String.self, forKey: .albumName)) ?? ""
        duration = try? c.decodeIfPresent(Double.self, forKey: .duration)
        instrumental = (try? c.decodeIfPresent(Bool.self, forKey: .instrumental)) ?? false
        plainLyrics = try? c.decodeIfPresent(String.self, forKey: .plainLyrics)
        syncedLyrics = try? c.decodeIfPresent(String.self, forKey: .syncedLyrics)
    }

    public init(
        trackName: String, artistName: String, albumName: String = "", duration: Double? = nil,
        instrumental: Bool = false, plainLyrics: String? = nil, syncedLyrics: String? = nil
    ) {
        self.trackName = trackName
        self.artistName = artistName
        self.albumName = albumName
        self.duration = duration
        self.instrumental = instrumental
        self.plainLyrics = plainLyrics
        self.syncedLyrics = syncedLyrics
    }
}

/// LRCLIB requests and response parsing (PLAN_M6 §3, §4.4). Pure.
public enum LRCLIBParser {
    static let base = "https://lrclib.net/api"
    /// Allowed difference between Spotify's and LRCLIB's duration when picking a search hit.
    public static let durationToleranceSeconds = 3.0

    // MARK: Requests

    /// `GET /api/get` with title, artist, album and duration in seconds.
    public static func getRequest(title: String, artist: String, album: String, durationMs: Int) -> HTTPRequestSpec? {
        var items = [("track_name", title), ("artist_name", artist)]
        if !album.isEmpty { items.append(("album_name", album)) }
        if durationMs > 0 { items.append(("duration", String(Int((Double(durationMs) / 1000).rounded())))) }
        return request("/get", items)
    }

    /// `GET /api/search` with title and artist.
    public static func searchRequest(title: String, artist: String) -> HTTPRequestSpec? {
        request("/search", [("track_name", title), ("artist_name", artist)])
    }

    private static func request(_ path: String, _ items: [(String, String)]) -> HTTPRequestSpec? {
        LyricsHTTP.url(base + path, items).map {
            HTTPRequestSpec(url: $0, headers: ["User-Agent": LyricsHTTP.userAgent, "Accept": "application/json"])
        }
    }

    // MARK: Responses

    /// One record from `/api/get`; `nil` when the body isn't a record.
    public static func parseRecord(_ data: Data) -> LRCLIBRecord? {
        try? JSONDecoder().decode(LRCLIBRecord.self, from: data)
    }

    /// Records from `/api/search`; elements that don't decode are skipped.
    public static func parseSearch(_ data: Data) -> [LRCLIBRecord] {
        struct Lossy: Decodable {
            let value: LRCLIBRecord?
            init(from decoder: any Decoder) throws { value = try? LRCLIBRecord(from: decoder) }
        }
        return ((try? JSONDecoder().decode([Lossy].self, from: data)) ?? []).compactMap(\.value)
    }

    /// Best search hit: title and artist must match; among those the closest duration within ±3 s
    /// (a hit without a duration is accepted last). `nil` when none qualifies.
    public static func bestMatch(_ records: [LRCLIBRecord], titles: [String], artist: String, durationMs: Int) -> LRCLIBRecord? {
        let seconds = Double(durationMs) / 1000
        let candidates = records.filter { r in
            titles.contains { TrackQuery.sameTitle($0, r.trackName) } && TrackQuery.sameArtist(artist, r.artistName)
        }
        func distance(_ r: LRCLIBRecord) -> Double? {
            guard durationMs > 0, let d = r.duration else { return nil }
            let diff = abs(d - seconds)
            return diff <= durationToleranceSeconds ? diff : .infinity
        }
        let scored = candidates.compactMap { r -> (LRCLIBRecord, Double)? in
            guard let d = distance(r) else { return durationMs > 0 ? (r, 1000) : (r, 0) }
            return d == .infinity ? nil : (r, d)
        }
        return scored.min { $0.1 < $1.1 }?.0
    }

    /// Display lines from `plainLyrics`, else from `syncedLyrics` with its stamps stripped. `nil` when neither has text.
    public static func lines(from record: LRCLIBRecord) -> [LyricLine]? {
        if let plain = record.plainLyrics, !plain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return LyricsText.lines(from: plain)
        }
        if let synced = record.syncedLyrics, !synced.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let lines = LyricsText.lines(from: stripTimestamps(synced))
            return lines.isEmpty ? nil : lines
        }
        return nil
    }

    /// `"[00:12.34] 보고 싶다"` → `"보고 싶다"`. Metadata tags (`[ar:…]`, `[by:…]`) are dropped.
    public static func stripTimestamps(_ synced: String) -> String {
        guard let stamp = try? NSRegularExpression(pattern: #"^(?:\s*\[\d+:\d+(?:[.:]\d+)?\])+\s*"#),
              let meta = try? NSRegularExpression(pattern: #"^\s*\[[A-Za-z]+:[^\]]*\]\s*$"#)
        else { return synced }
        return synced.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).compactMap { sub in
            let line = String(sub)
            let full = NSRange(line.startIndex..., in: line)
            if meta.firstMatch(in: line, range: full) != nil { return nil }
            return stamp.stringByReplacingMatches(in: line, range: full, withTemplate: "")
        }.joined(separator: "\n")
    }
}
