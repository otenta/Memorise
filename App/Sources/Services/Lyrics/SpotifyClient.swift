import Foundation
import MemoriseCore
import Observation
import UIKit

enum SpotifyError: Error, Equatable, LocalizedError {
    case notConnected
    case offline
    case rateLimited(retryAfter: Int)
    case quotaExceeded
    case http(Int)
    case unreadable

    var errorDescription: String? {
        switch self {
        case .notConnected: "Spotify isn't connected."
        case .offline: "You're offline."
        case let .rateLimited(n): "Spotify is busy, try again in \(n) s."
        case .quotaExceeded: "Spotify daily limit reached."
        case let .http(code): "Spotify answered \(code)."
        case .unreadable: "Spotify sent something unexpected."
        }
    }
}

/// One page of songs. `nextOffset` is `nil` on the last page.
struct SpotifyTrackPage: Sendable {
    var tracks: [TrackInfo]
    var nextOffset: Int?
}

/// One page of playlists. `nextOffset` is `nil` on the last page.
struct SpotifyPlaylistPage: Sendable {
    var playlists: [SpotifyPlaylist]
    var nextOffset: Int?
}

/// Songs of a playlist (one page), or the 2026 rule that Spotify only shares them for playlists you own.
enum PlaylistContents: Sendable {
    case tracks([TrackInfo], nextOffset: Int?)
    case notShared
}

/// Spotify sign-in state and Web API access for the Lyrics tab (PLAN_M6 §4.9).
@MainActor @Observable
final class SpotifyClient {
    enum State: Equatable {
        case notConfigured
        case disconnected
        case connecting
        case connected(displayName: String?)
    }

    enum PlayOutcome: Equatable {
        case playing
        /// No active device: the Spotify app was opened on the track instead.
        case openedSpotify
        /// Spotify refused playback (needs Premium).
        case notPremium
        case failed(String)
    }

    private(set) var state: State
    /// Signed-in Spotify user id, for the "playlists you own" rule.
    private(set) var userID: String?

    @ObservationIgnored private let auth: SpotifyAuth
    @ObservationIgnored private let http: any HTTPClient
    @ObservationIgnored private let openURL: @MainActor (URL) async -> Bool

    init(
        auth: SpotifyAuth? = nil,
        http: any HTTPClient = URLSessionHTTPClient(),
        openURL: @escaping @MainActor (URL) async -> Bool = { await UIApplication.shared.open($0) },
        initialState: State? = nil
    ) {
        let auth = auth ?? SpotifyAuth(clientID: LyricsConfig.spotifyClientID, http: http, secrets: KeychainStore())
        self.auth = auth
        self.http = http
        self.openURL = openURL
        state = initialState ?? (!auth.isConfigured ? .notConfigured : (auth.hasStoredSession ? .connected(displayName: nil) : .disconnected))
    }

    var isConnected: Bool {
        if case .connected = state { return true }
        return false
    }

    // MARK: Session

    /// Launch step: when a session is stored, confirm it and read the profile. Offline keeps it connected.
    func restore() async {
        guard case .connected = state else { return }
        await loadProfile()
    }

    func connect() async throws {
        guard auth.isConfigured else { state = .notConfigured; throw SpotifyAuthError.notConfigured }
        state = .connecting
        do {
            try await auth.signIn()
        } catch {
            state = .disconnected
            throw error
        }
        state = .connected(displayName: nil)
        await loadProfile()
    }

    /// Forgets the session and deletes the Keychain item.
    func disconnect() {
        auth.signOut()
        userID = nil
        if auth.isConfigured { state = .disconnected }
    }

    private func loadProfile() async {
        guard let data = try? await get({ SpotifyRequests.me(token: $0) }), let me = SpotifyDecoder.user(data) else { return }
        userID = me.id
        if isConnected { state = .connected(displayName: me.displayName ?? me.id) }
    }

    // MARK: Songs

    /// `nil` when nothing is playing, or it isn't a song.
    func nowPlaying() async throws -> SpotifyPlayback? {
        SpotifyDecoder.playback(try await get { SpotifyRequests.currentlyPlaying(token: $0) })
    }

    /// Last 50 plays, repeats removed (most recent first).
    func recent() async throws -> [TrackInfo] {
        let data = try await get { SpotifyRequests.recentlyPlayed(token: $0, limit: 50) }
        var seen = Set<String>()
        return (SpotifyDecoder.trackRows(data)?.tracks ?? []).filter { seen.insert($0.spotifyID).inserted }
    }

    /// 50 playlists from `offset`.
    func playlists(offset: Int = 0) async throws -> SpotifyPlaylistPage {
        let limit = 50
        let data = try await get { SpotifyRequests.playlists(token: $0, limit: limit, offset: offset) }
        let page = SpotifyDecoder.playlists(data)
        return SpotifyPlaylistPage(playlists: page?.playlists ?? [], nextOffset: page?.next == nil ? nil : offset + limit)
    }

    /// Whether Spotify will list this playlist's songs for the signed-in user.
    func canReadItems(of playlist: SpotifyPlaylist) -> Bool { playlist.isReadable(by: userID) }

    /// 100 songs from `offset`.
    func playlistItems(id: String, offset: Int = 0) async throws -> PlaylistContents {
        let limit = 100
        let data = try await get { SpotifyRequests.playlistItems(id: id, token: $0, limit: limit, offset: offset) }
        guard let rows = SpotifyDecoder.trackRows(data) else { return .notShared }
        return .tracks(rows.tracks, nextOffset: rows.next == nil ? nil : offset + limit)
    }

    func liked(offset: Int = 0) async throws -> SpotifyTrackPage {
        let limit = 50
        let data = try await get { SpotifyRequests.savedTracks(token: $0, limit: limit, offset: offset) }
        let rows = SpotifyDecoder.trackRows(data)
        return SpotifyTrackPage(tracks: rows?.tracks ?? [], nextOffset: rows?.next == nil ? nil : offset + limit)
    }

    func search(_ query: String) async throws -> [TrackInfo] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return [] }
        return SpotifyDecoder.search(try await get { SpotifyRequests.search(query: q, token: $0) })
    }

    /// One track with names localised for `language` (e.g. "ko-KR").
    func track(id: String, language: String?) async throws -> TrackInfo? {
        let data = try await get { SpotifyRequests.track(id: id, token: $0, language: language) }
        return SpotifyDecoder.track(data)?.trackInfo()
    }

    /// The Korean title of `track` (PLAN_M6 §4.4 step 1): `.same` when Spotify's `ko-KR` name equals the title,
    /// `.unknown` when the request failed.
    func koreanTitle(of track: TrackInfo) async -> KoreanTitleLookup {
        guard let ko = try? await self.track(id: track.spotifyID, language: "ko-KR") else { return .unknown }
        return ko.title == track.title || ko.title.isEmpty ? .same : .found(ko.title)
    }

    // MARK: Playback

    func play(trackID: String) async -> PlayOutcome {
        do {
            _ = try await get { SpotifyRequests.play(trackID: trackID, token: $0) }
            return .playing
        } catch SpotifyError.http(403) {
            return .notPremium
        } catch SpotifyError.http(404) {
            // NO_ACTIVE_DEVICE: let the Spotify app start the track.
            guard let uri = SpotifyRequests.trackURI(trackID), await openURL(uri) else {
                return .failed("Open Spotify, then pick the song again.")
            }
            return .openedSpotify
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    // MARK: Requests

    /// Sends an authorised request. 401 → one refresh and retry; a refresh Spotify refuses → disconnected.
    /// 429 and other failures become `SpotifyError`s.
    private func get(_ build: (String) -> HTTPRequestSpec?) async throws -> Data {
        guard auth.isConfigured else { throw SpotifyError.notConnected }
        var token = try await accessToken()
        for attempt in 0..<2 {
            guard let spec = build(token) else { throw SpotifyError.unreadable }
            let response: HTTPResponse
            do {
                response = try await http.send(spec)
            } catch HTTPError.offline {
                throw SpotifyError.offline
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                throw SpotifyError.offline
            }
            if response.status == 401, attempt == 0 {
                token = try await refreshedToken()
                continue
            }
            if response.status == 401 { lostSession(); throw SpotifyError.notConnected }
            if response.status == 429 { throw rateLimit(response) }
            guard response.isSuccess else { throw SpotifyError.http(response.status) }
            return response.data
        }
        throw SpotifyError.notConnected
    }

    private func accessToken() async throws -> String {
        do {
            return try await auth.validAccessToken()
        } catch SpotifyAuthError.offline {
            throw SpotifyError.offline
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            if case SpotifyAuthError.rejected = error { lostSession() }
            throw SpotifyError.notConnected
        }
    }

    private func refreshedToken() async throws -> String {
        do {
            return try await auth.refreshAfterUnauthorized()
        } catch SpotifyAuthError.offline {
            throw SpotifyError.offline
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            if case SpotifyAuthError.rejected = error { lostSession() }
            throw SpotifyError.notConnected
        }
    }

    /// The grant is gone (revoked, or app removed in Spotify account settings): back to Connect.
    private func lostSession() {
        auth.signOut()
        userID = nil
        state = .disconnected
    }

    private func rateLimit(_ response: HTTPResponse) -> SpotifyError {
        if SpotifyDecoder.errorReason(response.data) == "QUOTA_EXCEEDED" { return .quotaExceeded }
        return .rateLimited(retryAfter: max(1, response.header("retry-after").flatMap { Int($0) } ?? 5))
    }
}
