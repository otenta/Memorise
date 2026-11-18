import Foundation

/// Spotify Web API response models, using the 2026 field names (PLAN_M6 §3, §4.9).
/// Every optional field tolerates being absent; list elements that don't decode are skipped.

/// Decodes one array element without failing the whole array.
private struct LossyElement<T: Decodable>: Decodable {
    let value: T?
    init(from decoder: any Decoder) throws { value = try? T(from: decoder) }
}

public struct SpotifyToken: Hashable, Sendable, Decodable {
    public var accessToken: String
    public var expiresIn: Int
    /// Absent on some refresh responses: keep the old one then.
    public var refreshToken: String?
    public var scope: String?

    private enum CodingKeys: String, CodingKey {
        case accessToken = "access_token", expiresIn = "expires_in", refreshToken = "refresh_token", scope
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        accessToken = try c.decode(String.self, forKey: .accessToken)
        expiresIn = (try? c.decodeIfPresent(Int.self, forKey: .expiresIn)) ?? 3600
        refreshToken = try? c.decodeIfPresent(String.self, forKey: .refreshToken)
        scope = try? c.decodeIfPresent(String.self, forKey: .scope)
    }
}

public struct SpotifyUser: Hashable, Sendable, Decodable {
    public var id: String
    public var displayName: String?

    private enum CodingKeys: String, CodingKey { case id, displayName = "display_name" }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decodeIfPresent(String.self, forKey: .id)) ?? ""
        displayName = try? c.decodeIfPresent(String.self, forKey: .displayName)
    }
}

public struct SpotifyImage: Hashable, Sendable, Decodable {
    public var url: String
    public var width: Int?
    public var height: Int?
}

public struct SpotifyTrack: Hashable, Sendable, Decodable {
    public struct Artist: Hashable, Sendable, Decodable { public var name: String? }
    public struct Album: Hashable, Sendable, Decodable {
        public var name: String?
        public var releaseDate: String?
        public var images: [SpotifyImage]?

        private enum CodingKeys: String, CodingKey { case name, releaseDate = "release_date", images }
    }

    public var id: String?
    public var name: String?
    /// "track" or "episode"; absent is read as a track.
    public var type: String?
    public var durationMs: Int?
    public var artists: [Artist]?
    public var album: Album?

    private enum CodingKeys: String, CodingKey { case id, name, type, durationMs = "duration_ms", artists, album }

    /// Podcast episodes and local files have no usable id.
    public var isTrack: Bool { (type ?? "track") == "track" && !(id ?? "").isEmpty }

    /// `titleKo` comes from a second `ko-KR` request (§4.4); stored only when it differs.
    public func trackInfo(titleKo: String? = nil) -> TrackInfo? {
        guard isTrack, let id, let name else { return nil }
        let ko = titleKo.flatMap { $0 != name && !$0.isEmpty ? $0 : nil }
        let year = album?.releaseDate.flatMap { Int($0.prefix(4)) }
        return TrackInfo(
            spotifyID: id, title: name, titleKo: ko,
            artists: (artists ?? []).compactMap(\.name), album: album?.name ?? "",
            durationMs: durationMs ?? 0, releaseYear: year, artworkURL: Self.artwork(album?.images ?? []))
    }

    /// Smallest image at least 64 px wide; the largest one when none is that wide; images without a size count as wide.
    static func artwork(_ images: [SpotifyImage]) -> String? {
        let sized = images.filter { ($0.width ?? 64) >= 64 }.sorted { ($0.width ?? .max) < ($1.width ?? .max) }
        return (sized.first ?? images.max { ($0.width ?? 0) < ($1.width ?? 0) })?.url
    }
}

/// A paged list. `items` is `nil` when Spotify withholds it (playlists the user doesn't own, 2026).
public struct SpotifyPage<Element: Decodable & Sendable>: Sendable, Decodable {
    public var items: [Element]?
    public var next: String?
    public var total: Int?
    public var offset: Int?

    private enum CodingKeys: String, CodingKey { case items, next, total, offset }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        items = (try? c.decodeIfPresent([LossyElement<Element>].self, forKey: .items))?.compactMap(\.value)
        next = try? c.decodeIfPresent(String.self, forKey: .next)
        total = try? c.decodeIfPresent(Int.self, forKey: .total)
        offset = try? c.decodeIfPresent(Int.self, forKey: .offset)
    }
}

/// A row of `recently-played` and `me/tracks` (`track`), or of `playlists/{id}/items` (`item`, 2026).
public struct SpotifyTrackRow: Sendable, Decodable {
    public var track: SpotifyTrack?
    private enum CodingKeys: String, CodingKey { case track, item }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        track = (try? c.decodeIfPresent(SpotifyTrack.self, forKey: .item))
            ?? (try? c.decodeIfPresent(SpotifyTrack.self, forKey: .track))
    }
}

public struct SpotifyPlaylist: Hashable, Sendable, Decodable {
    public struct Owner: Hashable, Sendable, Decodable { public var id: String? }
    public var id: String
    public var name: String
    public var ownerID: String?
    public var collaborative: Bool
    public var images: [SpotifyImage]

    private enum CodingKeys: String, CodingKey { case id, name, owner, collaborative, images }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = (try? c.decodeIfPresent(String.self, forKey: .name)) ?? ""
        ownerID = (try? c.decodeIfPresent(Owner.self, forKey: .owner))?.id
        collaborative = (try? c.decodeIfPresent(Bool.self, forKey: .collaborative)) ?? false
        images = (try? c.decodeIfPresent([SpotifyImage].self, forKey: .images)) ?? []
    }

    /// Spotify only returns songs for playlists the user owns or collaborates on.
    public func isReadable(by userID: String?) -> Bool {
        collaborative || (userID != nil && ownerID == userID)
    }

    public var artworkURL: String? { SpotifyTrack.artwork(images) }
}

/// Spotify's playback state for `currently-playing`.
public struct SpotifyCurrentlyPlaying: Sendable, Decodable {
    public var item: SpotifyTrack?
    public var isPlaying: Bool
    public var progressMs: Int?

    private enum CodingKeys: String, CodingKey { case item, isPlaying = "is_playing", progressMs = "progress_ms" }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        item = try? c.decodeIfPresent(SpotifyTrack.self, forKey: .item)
        isPlaying = (try? c.decodeIfPresent(Bool.self, forKey: .isPlaying)) ?? false
        progressMs = try? c.decodeIfPresent(Int.self, forKey: .progressMs)
    }
}

private struct SpotifySearchResponse: Decodable {
    var tracks: SpotifyPage<SpotifyTrack>?
}

private struct SpotifyErrorBody: Decodable {
    struct Inner: Decodable {
        var status: Int?
        var message: String?
        var reason: String?
    }
    var error: Inner?
    var reason: String?
}

/// What Spotify is playing: the song and whether it is playing or paused.
public struct SpotifyPlayback: Hashable, Sendable {
    public var track: TrackInfo
    public var isPlaying: Bool
    /// Where the song is, in milliseconds. Not persisted. `nil` when Spotify didn't say.
    public var progressMs: Int?

    public init(track: TrackInfo, isPlaying: Bool, progressMs: Int? = nil) {
        self.track = track
        self.isPlaying = isPlaying
        self.progressMs = progressMs
    }

    /// Milliseconds until the song ends, or `nil` when the duration or the progress is unknown or ≤ 0.
    public var remainingMs: Int? {
        guard let progressMs, track.durationMs > 0 else { return nil }
        let r = track.durationMs - progressMs
        return r > 0 ? r : nil
    }

    /// What the Now playing card shows: the song and playing/paused. Progress alone is not a visible change.
    public func sameCard(as other: SpotifyPlayback) -> Bool {
        track.spotifyID == other.track.spotifyID && isPlaying == other.isPlaying
    }
}

/// Decoding for every Spotify response body.
public enum SpotifyDecoder {
    public static func token(_ data: Data) -> SpotifyToken? { try? JSONDecoder().decode(SpotifyToken.self, from: data) }
    public static func user(_ data: Data) -> SpotifyUser? { try? JSONDecoder().decode(SpotifyUser.self, from: data) }
    public static func track(_ data: Data) -> SpotifyTrack? { try? JSONDecoder().decode(SpotifyTrack.self, from: data) }

    /// `nil` when nothing is playing (Spotify answers 204 with an empty body) or the item isn't a track.
    public static func currentlyPlaying(_ data: Data) -> TrackInfo? { playback(data)?.track }

    /// Like `currentlyPlaying`, with the playing/paused flag.
    public static func playback(_ data: Data) -> SpotifyPlayback? {
        guard !data.isEmpty, let p = try? JSONDecoder().decode(SpotifyCurrentlyPlaying.self, from: data),
              let track = p.item?.trackInfo() else { return nil }
        return SpotifyPlayback(track: track, isPlaying: p.isPlaying, progressMs: p.progressMs)
    }

    /// Tracks of a `recently-played`, `me/tracks` or `playlists/{id}/items` page, in order, non-tracks skipped.
    /// `nil` items (playlist the user doesn't own) → `nil`, so the UI can show the note.
    public static func trackRows(_ data: Data) -> (tracks: [TrackInfo], next: String?)? {
        guard let page = try? JSONDecoder().decode(SpotifyPage<SpotifyTrackRow>.self, from: data), let items = page.items
        else { return nil }
        return (items.compactMap { $0.track?.trackInfo() }, page.next)
    }

    public static func playlists(_ data: Data) -> (playlists: [SpotifyPlaylist], next: String?)? {
        guard let page = try? JSONDecoder().decode(SpotifyPage<SpotifyPlaylist>.self, from: data), let items = page.items
        else { return nil }
        return (items, page.next)
    }

    public static func search(_ data: Data) -> [TrackInfo] {
        ((try? JSONDecoder().decode(SpotifySearchResponse.self, from: data))?.tracks?.items ?? []).compactMap { $0.trackInfo() }
    }

    /// The `reason` of a player error body (`{"error":{"reason":"NO_ACTIVE_DEVICE"}}`), or `nil` when there is none.
    public static func playerErrorReason(_ data: Data) -> String? { errorReason(data) }

    /// Spotify's `reason` (e.g. `NO_ACTIVE_DEVICE`, `QUOTA_EXCEEDED`) from an error body, wherever it sits.
    public static func errorReason(_ data: Data) -> String? {
        guard let b = try? JSONDecoder().decode(SpotifyErrorBody.self, from: data) else { return nil }
        return b.error?.reason ?? b.reason
    }
}
