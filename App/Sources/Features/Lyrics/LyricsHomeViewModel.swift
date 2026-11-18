import MemoriseCore
import Observation
import SwiftUI

/// Where a push in the Lyrics tab goes.
enum LyricsRoute: Hashable {
    case reader(TrackInfo)
    case playlist(SpotifyPlaylist)
}

/// Loading state of one picker list.
enum LyricsLoad<Value> {
    case idle
    case loading
    case loaded(Value)
    case failed(String)

    var value: Value? {
        if case let .loaded(v) = self { return v }
        return nil
    }

    var isLoading: Bool {
        if case .loading = self { return true }
        return false
    }
}

enum LyricsSource: String, CaseIterable, Identifiable {
    case recent = "Recent"
    case playlists = "Playlists"
    case liked = "Liked"

    var id: String { rawValue }
}

/// State of the Lyrics tab's song picker (PLAN_M6 §4.9, L6).
@MainActor @Observable
final class LyricsHomeViewModel {
    var path: [LyricsRoute] = []
    var source: LyricsSource = .recent
    var query = ""

    private(set) var nowPlaying: LyricsLoad<TrackInfo?> = .idle
    private(set) var recent: LyricsLoad<[TrackInfo]> = .idle
    private(set) var playlists: LyricsLoad<[SpotifyPlaylist]> = .idle
    private(set) var liked: LyricsLoad<[TrackInfo]> = .idle
    private(set) var likedNextOffset: Int?
    private(set) var loadingMoreLiked = false
    private(set) var results: LyricsLoad<[TrackInfo]> = .idle
    /// One-line note after tapping a song (not Premium, Spotify opened, or a failure).
    private(set) var notice: String?
    private(set) var connectError: String?

    @ObservationIgnored private let spotify: SpotifyClient

    init(spotify: SpotifyClient) {
        self.spotify = spotify
    }

    var isSearching: Bool { !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    // MARK: Connect

    func connect() async {
        connectError = nil
        do {
            try await spotify.connect()
            await refreshAll()
        } catch SpotifyAuthError.cancelled {
            return
        } catch {
            connectError = Self.message(error)
        }
    }

    // MARK: Loading

    func refreshAll() async {
        async let now: Void = refreshNowPlaying()
        async let rec: Void = loadRecent()
        _ = await (now, rec)
        switch source {
        case .recent: break
        case .playlists: await loadPlaylists()
        case .liked: await loadLiked()
        }
    }

    func refreshNowPlaying() async {
        if nowPlaying.value == nil { nowPlaying = .loading }
        do {
            nowPlaying = .loaded(try await spotify.nowPlaying())
        } catch is CancellationError {
            return
        } catch {
            nowPlaying = .failed(Self.message(error))
        }
    }

    func loadRecent(force: Bool = false) async {
        if !force, recent.value != nil { return }
        recent = .loading
        do {
            recent = .loaded(try await spotify.recent())
        } catch is CancellationError {
            recent = .idle
        } catch {
            recent = .failed(Self.message(error))
        }
    }

    func loadPlaylists(force: Bool = false) async {
        if !force, playlists.value != nil { return }
        playlists = .loading
        do {
            playlists = .loaded(try await spotify.playlists())
        } catch is CancellationError {
            playlists = .idle
        } catch {
            playlists = .failed(Self.message(error))
        }
    }

    func loadLiked(force: Bool = false) async {
        if !force, liked.value != nil { return }
        liked = .loading
        do {
            let page = try await spotify.liked(offset: 0)
            liked = .loaded(page.tracks)
            likedNextOffset = page.nextOffset
        } catch is CancellationError {
            liked = .idle
        } catch {
            liked = .failed(Self.message(error))
        }
    }

    func loadMoreLiked() async {
        guard let offset = likedNextOffset, !loadingMoreLiked, var current = liked.value else { return }
        loadingMoreLiked = true
        defer { loadingMoreLiked = false }
        do {
            let page = try await spotify.liked(offset: offset)
            let known = Set(current.map(\.spotifyID))
            current += page.tracks.filter { !known.contains($0.spotifyID) }
            liked = .loaded(current)
            likedNextOffset = page.nextOffset
        } catch is CancellationError {
            return
        } catch {
            notice = Self.message(error)
        }
    }

    /// Debounced by the caller (`.task(id:)` + sleep).
    func runSearch() async {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { results = .idle; return }
        results = .loading
        do {
            results = .loaded(try await spotify.search(q))
        } catch is CancellationError {
            return
        } catch {
            results = .failed(Self.message(error))
        }
    }

    func loadSource() async {
        switch source {
        case .recent: await loadRecent()
        case .playlists: await loadPlaylists()
        case .liked: await loadLiked()
        }
    }

    // MARK: Opening a song

    /// Starts the song in Spotify (unless it's already playing), then opens the reader.
    func open(_ track: TrackInfo, play: Bool) async {
        notice = nil
        if play {
            switch await spotify.play(trackID: track.spotifyID) {
            case .playing: break
            case .openedSpotify: notice = "Opened in Spotify."
            case .notPremium: notice = "Spotify needs Premium to start songs from here. Press play in Spotify."
            case let .failed(message): notice = message
            }
        }
        path.append(.reader(track))
    }

    func dismissNotice() { notice = nil }

    func canReadItems(of playlist: SpotifyPlaylist) -> Bool { spotify.canReadItems(of: playlist) }

    func playlistItems(id: String) async throws -> PlaylistContents {
        try await spotify.playlistItems(id: id)
    }

    // MARK: Messages

    static func message(_ error: Error) -> String {
        if let e = error as? SpotifyError {
            switch e {
            case .offline: return "You're offline."
            default: return e.errorDescription ?? "Something went wrong."
            }
        }
        if let e = error as? SpotifyAuthError {
            switch e {
            case .offline: return "You're offline."
            case .notConfigured: return "Spotify isn't set up yet."
            case .rejected, .notSignedIn: return "Spotify sign-in expired. Connect again."
            case .cancelled: return ""
            case let .failed(m): return m
            }
        }
        return error.localizedDescription
    }
}
