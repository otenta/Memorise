import Foundation
import MemoriseCore
import Observation

/// What Spotify is playing, shared by the Lyrics home and the reader (PLAN_R10 LA4).
///
/// The state lives here, not in a view model, because two screens show it. `watch()` polls while the screen that
/// runs it is visible; cancelling that task stops the polling.
@MainActor @Observable
final class NowPlayingMonitor {
    private(set) var state: LyricsLoad<SpotifyPlayback?> = .idle

    @ObservationIgnored private let spotify: SpotifyClient
    /// Bumped by `reset()`, so a response for the old account can't fill `state`.
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var inFlight = false

    init(spotify: SpotifyClient) {
        self.spotify = spotify
    }

    /// Asks Spotify once. Returns what it found, for the poll delay. Skips the request (and returns
    /// `.pausedOrNothing`) while another refresh is in flight, so the poll loop, the ↻ button and a post-play
    /// refresh never overlap. `showLoading` puts a spinner in the card when nothing is loaded yet.
    @discardableResult
    func refresh(showLoading: Bool = false) async -> NowPlayingPoll.Last {
        guard !inFlight else { return .pausedOrNothing }
        inFlight = true
        defer { inFlight = false }
        let gen = generation
        if case .idle = state { state = .loading } else if showLoading, state.value == nil { state = .loading }
        do {
            let playing = try await spotify.nowPlaying()
            guard gen == generation else { return .pausedOrNothing }
            assign(.loaded(playing))
            guard let playing, playing.isPlaying else { return .pausedOrNothing }
            return .playing(remainingMs: playing.remainingMs)
        } catch is CancellationError {
            return .pausedOrNothing
        } catch {
            guard gen == generation else { return .failed }
            assign(.failed(LyricsHomeViewModel.message(error)))
            if case let SpotifyError.rateLimited(retryAfter) = error { return .rateLimited(retryAfter: retryAfter) }
            return .failed
        }
    }

    /// Polls until the task is cancelled.
    func watch() async {
        while !Task.isCancelled {
            let last = await refresh()
            try? await Task.sleep(for: .seconds(NowPlayingPoll.delaySeconds(after: last)))
        }
    }

    /// Refreshes after a short wait. Used after a song was started from the picker.
    func refreshSoon() {
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.5))
            await self?.refresh()
        }
    }

    /// Forgets everything (Spotify was disconnected).
    func reset() {
        generation &+= 1
        state = .idle
    }

    /// Assigns `new` only when something visible changes: the song, playing/paused, nothing ↔ something, or
    /// failed ↔ loaded. Progress alone never triggers a re-render.
    private func assign(_ new: LyricsLoad<SpotifyPlayback?>) {
        switch (state, new) {
        case let (.loaded(old), .loaded(fresh)):
            switch (old, fresh) {
            case (nil, nil): return
            case let (a?, b?) where a.sameCard(as: b): return
            default: break
            }
        case (.failed, .failed):
            return
        default:
            break
        }
        state = new
    }

    #if DEBUG
    /// Previews only.
    func previewNowPlaying(_ playback: SpotifyPlayback?) { state = .loaded(playback) }
    #endif
}
