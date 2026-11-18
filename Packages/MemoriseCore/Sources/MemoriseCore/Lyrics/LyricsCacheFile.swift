import Foundation

/// On-disk cache entry for one track: `Application Support/LyricsCache/<spotifyID>.json` (PLAN_M6 §4.7).
/// Never exported (copyright). Decoding is tolerant; the store deletes and refetches an unreadable file.
public struct LyricsCacheFile: Hashable, Codable, Sendable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var track: TrackInfo
    /// "available" or "notAvailable".
    public var result: String
    public var reason: LyricsResult.Reason?
    public var document: LyricsDocument?
    /// Machine glosses by token text (PLAN_M6 §4.8).
    public var glosses: [String: String]
    public var fetchedAt: Date

    public init(track: TrackInfo, result: LyricsResult, glosses: [String: String] = [:], fetchedAt: Date) {
        schemaVersion = Self.currentSchemaVersion
        self.track = track
        self.glosses = glosses
        self.fetchedAt = fetchedAt
        switch result {
        case let .available(doc):
            self.result = "available"
            reason = nil
            document = doc
        case let .notAvailable(r):
            self.result = "notAvailable"
            reason = r
            document = nil
        }
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, track, result, reason, document, glosses, fetchedAt
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = (try? c.decodeIfPresent(Int.self, forKey: .schemaVersion)) ?? Self.currentSchemaVersion
        track = (try? c.decodeIfPresent(TrackInfo.self, forKey: .track)) ?? TrackInfo(spotifyID: "", title: "")
        result = (try? c.decodeIfPresent(String.self, forKey: .result)) ?? ""
        reason = try? c.decodeIfPresent(LyricsResult.Reason.self, forKey: .reason)
        document = try? c.decodeIfPresent(LyricsDocument.self, forKey: .document)
        glosses = (try? c.decodeIfPresent([String: String].self, forKey: .glosses)) ?? [:]
        let t = (try? c.decodeIfPresent(Double.self, forKey: .fetchedAt)) ?? 0
        fetchedAt = Date(timeIntervalSince1970: t)
    }

    /// `fetchedAt` is stored as seconds since 1970, so no date strategy is needed.
    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(schemaVersion, forKey: .schemaVersion)
        try c.encode(track, forKey: .track)
        try c.encode(result, forKey: .result)
        try c.encodeIfPresent(reason, forKey: .reason)
        try c.encodeIfPresent(document, forKey: .document)
        try c.encode(glosses, forKey: .glosses)
        try c.encode(fetchedAt.timeIntervalSince1970, forKey: .fetchedAt)
    }

    /// The cached result, or `nil` when the file is unusable (unknown kind, or "available" with no document).
    public var lyricsResult: LyricsResult? {
        switch result {
        case "available": document.map(LyricsResult.available)
        case "notAvailable": .notAvailable(reason ?? .notFound)
        default: nil
        }
    }

    /// Available entries with an English page never expire. "Not available" entries are trusted for
    /// `notAvailableTTLDays`, and available entries without English for `missingEnglishTTLDays`.
    public func isFresh(now: Date) -> Bool {
        guard lyricsResult != nil else { return false }
        let days: Int
        if result != "available" {
            days = LyricsConstants.notAvailableTTLDays
        } else if document?.english == nil {
            days = LyricsConstants.missingEnglishTTLDays
        } else {
            return true
        }
        return now.timeIntervalSince(fetchedAt) < Double(days) * 86_400
    }

    /// Decodes a file, or `nil` when it is unreadable or has no usable result.
    public static func decode(_ data: Data) -> LyricsCacheFile? {
        guard let f = try? JSONDecoder().decode(LyricsCacheFile.self, from: data), f.lyricsResult != nil, !f.track.spotifyID.isEmpty
        else { return nil }
        return f
    }

    public func encoded() throws -> Data {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys]
        return try e.encode(self)
    }
}
