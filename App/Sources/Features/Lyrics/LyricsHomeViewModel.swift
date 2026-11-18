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

    private(set) var recent: LyricsLoad<[TrackInfo]> = .idle
    private(set) var playlists: LyricsLoad<[SpotifyPlaylist]> = .idle
    private(set) var liked: LyricsLoad<[TrackInfo]> = .idle
    private(set) var likedNextOffset: Int?
    private(set) var loadingMoreLiked = false
    private(set) var results: LyricsLoad<[TrackInfo]> = .idle
    /// One-line note after tapping a song (not Premium, Spotify opened, or a failure).
    private(set) var notice: String?
    private(set) var connectError: String?
    private(set) var playlistsNextOffset: Int?
    private(set) var loadingMorePlaylists = false
    /// Songs of the open playlist loaded so far (all pages), and where the next page starts.
    private(set) var playlistTracks: [TrackInfo] = []
    private(set) var itemsNextOffset: Int?
    private(set) var loadingMoreItems = false
    @ObservationIgnored private var openPlaylistID: String?
    /// A refresh failed while a list was already on screen: the list stays, this says why.
    private(set) var listError: String?
    /// Lists that weren't visible during the last refresh; each reloads once when it is opened.
    private(set) var staleSources: Set<LyricsSource> = []
    /// Bumped by `reset()`, so a request still in flight for the old account can't fill a list.
    @ObservationIgnored private var generation = 0

    @ObservationIgnored private let spotify: SpotifyClient
    @ObservationIgnored private let monitor: NowPlayingMonitor

    init(spotify: SpotifyClient, nowPlaying: NowPlayingMonitor) {
        self.spotify = spotify
        monitor = nowPlaying
    }

    /// What Spotify is playing. The state lives in the shared monitor (the reader shows it too).
    var nowPlaying: LyricsLoad<SpotifyPlayback?> { monitor.state }

    /// The ↻ button on the card.
    func refreshNowPlaying() async { await monitor.refresh(showLoading: true) }

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
        listError = nil
        async let now: Void = refreshNowPlaying()
        async let rec: Void = loadRecent(force: true)
        _ = await (now, rec)
        var stale: Set<LyricsSource> = [.playlists, .liked]
        switch source {
        case .recent: break
        case .playlists: await loadPlaylists(force: true); stale.remove(.playlists)
        case .liked: await loadLiked(force: true); stale.remove(.liked)
        }
        staleSources.formUnion(stale)
    }

    func loadRecent(force: Bool = false) async {
        if !force, recent.value != nil { return }
        let gen = generation
        if recent.value == nil { recent = .loading }
        do {
            let tracks = try await spotify.recent()
            guard gen == generation else { return }
            recent = .loaded(tracks)
        } catch is CancellationError {
            if gen == generation, recent.value == nil { recent = .idle }
        } catch {
            guard gen == generation else { return }
            fail(&recent, error)
        }
    }

    func loadPlaylists(force: Bool = false) async {
        if !force, playlists.value != nil { return }
        let gen = generation
        if playlists.value == nil { playlists = .loading }
        do {
            let page = try await spotify.playlists(offset: 0)
            guard gen == generation else { return }
            playlists = .loaded(page.playlists)
            playlistsNextOffset = page.nextOffset
            staleSources.remove(.playlists)
        } catch is CancellationError {
            if gen == generation, playlists.value == nil { playlists = .idle }
        } catch {
            guard gen == generation else { return }
            fail(&playlists, error)
        }
    }

    func loadLiked(force: Bool = false) async {
        if !force, liked.value != nil { return }
        let gen = generation
        if liked.value == nil { liked = .loading }
        do {
            let page = try await spotify.liked(offset: 0)
            guard gen == generation else { return }
            liked = .loaded(page.tracks)
            likedNextOffset = page.nextOffset
            staleSources.remove(.liked)
        } catch is CancellationError {
            if gen == generation, liked.value == nil { liked = .idle }
        } catch {
            guard gen == generation else { return }
            fail(&liked, error)
        }
    }

    /// A failed load replaces an empty list with the error, but never wipes a list already on screen.
    private func fail<V>(_ load: inout LyricsLoad<V>, _ error: Error) {
        if load.value == nil {
            load = .failed(Self.message(error))
        } else {
            listError = Self.message(error)
        }
    }

    /// Forgets everything the previous account loaded (Spotify was disconnected).
    func reset() {
        generation &+= 1
        monitor.reset()
        recent = .idle
        playlists = .idle
        liked = .idle
        likedNextOffset = nil
        loadingMoreLiked = false
        playlistsNextOffset = nil
        loadingMorePlaylists = false
        playlistTracks = []
        itemsNextOffset = nil
        loadingMoreItems = false
        openPlaylistID = nil
        results = .idle
        staleSources = []
        listError = nil
        notice = nil
        connectError = nil
        query = ""
        path = []
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

    func loadMorePlaylists() async {
        guard let offset = playlistsNextOffset, !loadingMorePlaylists, var current = playlists.value else { return }
        let gen = generation
        loadingMorePlaylists = true
        defer { loadingMorePlaylists = false }
        do {
            let page = try await spotify.playlists(offset: offset)
            guard gen == generation else { return }
            let known = Set(current.map(\.id))
            current += page.playlists.filter { !known.contains($0.id) }
            playlists = .loaded(current)
            playlistsNextOffset = page.nextOffset
        } catch is CancellationError {
            return
        } catch {
            if gen == generation { notice = Self.message(error) }
        }
    }

    /// Next page of the open playlist's songs.
    func loadMoreItems() async {
        guard let offset = itemsNextOffset, let id = openPlaylistID, !loadingMoreItems else { return }
        loadingMoreItems = true
        defer { loadingMoreItems = false }
        do {
            let contents = try await spotify.playlistItems(id: id, offset: offset)
            guard openPlaylistID == id, case let .tracks(tracks, next) = contents else { return }
            let known = Set(playlistTracks.map(\.spotifyID))
            playlistTracks += tracks.filter { !known.contains($0.spotifyID) }
            itemsNextOffset = next
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
        let stale = staleSources.contains(source)
        switch source {
        case .recent: await loadRecent(force: stale)
        case .playlists: await loadPlaylists(force: stale)
        case .liked: await loadLiked(force: stale)
        }
    }

    // MARK: Opening a song

    /// Swaps the open reader for `track`'s (the reader's Show lyrics button). Back still returns to where the first
    /// reader came from. Never starts playback.
    func showLyrics(for track: TrackInfo) {
        if case .reader? = path.last {
            path[path.count - 1] = .reader(track)
        } else {
            path.append(.reader(track))
        }
    }

    /// Opens the reader at once, then starts the song in Spotify in the background (unless it is already playing).
    /// A failed start is reported in `notice`; it never delays or blocks the reader.
    func open(_ track: TrackInfo, play: Bool) async {
        notice = nil
        path.append(.reader(track))
        guard play else { return }
        let spotify = spotify
        let gen = generation
        Task { [weak self] in
            let outcome = await spotify.play(trackID: track.spotifyID)
            guard let self, gen == self.generation else { return }
            switch outcome {
            case .playing: self.monitor.refreshSoon()
            case .openedSpotify: self.notice = "Opened in Spotify."
            case .notPremium: self.notice = "Spotify needs Premium to start songs from here. Press play in Spotify."
            case let .failed(message): self.notice = message
            }
        }
    }

    func dismissNotice() { notice = nil }

    func canReadItems(of playlist: SpotifyPlaylist) -> Bool { spotify.canReadItems(of: playlist) }

    /// First page of a playlist's songs. Also becomes the open playlist for `loadMoreItems()`.
    func playlistItems(id: String) async throws -> PlaylistContents {
        let contents = try await spotify.playlistItems(id: id, offset: 0)
        openPlaylistID = id
        switch contents {
        case let .tracks(tracks, next):
            playlistTracks = tracks
            itemsNextOffset = next
        case .notShared:
            playlistTracks = []
            itemsNextOffset = nil
        }
        return contents
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
