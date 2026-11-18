import Foundation
import MemoriseCore
import Observation

/// What Spotify is playing, shared by the Lyrics home and the reader (PLAN_R10 LA4).
///
/// The state lives here, not in a view model, because two screens show it. `watch()` polls while the screen that
/// runs it is visible; cancelling that task stops the polling.
/// Why a player command didn't work (PLAN_R12). Shown by the Lyrics home and the reader.
enum PlayerNotice: Equatable {
    /// Spotify isn't running on any device: the UI offers an Open Spotify button (P-10).
    case noDevice
    case notPremium
    case failed(String)
}

@MainActor @Observable
final class NowPlayingMonitor {
    private(set) var state: LyricsLoad<SpotifyPlayback?> = .idle
    private(set) var notice: PlayerNotice?
    /// A command is running: further taps are ignored (no queue).
    private(set) var commandInFlight = false
    /// True after next or previous, until the track changes or 3 s pass.
    private(set) var switching = false

    @ObservationIgnored private let spotify: SpotifyClient
    /// Bumped by `reset()`, so a response for the old account can't fill `state`.
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var inFlight = false
    /// Bumped by every command. A refresh that started before a command can't write its stale answer.
    @ObservationIgnored private var commandStamp = 0
    @ObservationIgnored private var switchingTask: Task<Void, Never>?

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
        let stamp = commandStamp
        if case .idle = state { state = .loading } else if showLoading, state.value == nil { state = .loading }
        do {
            let playing = try await spotify.nowPlaying()
            guard gen == generation, stamp == commandStamp else { return .pausedOrNothing }
            assign(.loaded(playing))
            guard let playing, playing.isPlaying else { return .pausedOrNothing }
            return .playing(remainingMs: playing.remainingMs)
        } catch is CancellationError {
            return .pausedOrNothing
        } catch {
            guard gen == generation, stamp == commandStamp else { return .failed }
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

    /// Refreshes after a short wait (`seconds`). Waits for a refresh already in flight instead of skipping.
    func refreshSoon(after seconds: Double = 1.5) {
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            await self?.refreshWhenFree()
        }
    }

    private func refreshWhenFree() async {
        for _ in 0..<6 {
            if !inFlight { await refresh(); return }
            try? await Task.sleep(for: .milliseconds(300))
        }
    }

    // MARK: Commands (PLAN_R12 PC1)

    /// Starts `track` (in `context`, so next and previous follow a playlist). Memorise stays on screen.
    func play(_ track: TrackInfo, context: PlayContext) async {
        notice = nil
        commandStamp &+= 1
        let outcome = await spotify.play(trackID: track.spotifyID, context: context)
        finish(outcome)
    }

    /// Pauses or resumes at once on screen, then tells Spotify. Undone with a notice when Spotify refuses.
    func togglePlayPause() async {
        guard !commandInFlight, case let .loaded(current?) = state else { return }
        commandInFlight = true
        defer { commandInFlight = false }
        notice = nil
        commandStamp &+= 1
        var flipped = current
        flipped.isPlaying.toggle()
        state = .loaded(flipped)
        let outcome = flipped.isPlaying ? await spotify.resume() : await spotify.pause()
        if outcome == .playing {
            refreshSoon(after: 0.8)
        } else {
            // Undo, unless something else changed the card meanwhile.
            if case let .loaded(now?) = state, now.sameCard(as: flipped) { state = .loaded(current) }
            finish(outcome)
        }
    }

    func skipNext() async { await skip { await $0.next() } }

    func skipPrevious() async { await skip { await $0.previous() } }

    func dismissNotice() { notice = nil }

    private func skip(_ send: (SpotifyClient) async -> SpotifyClient.PlayOutcome) async {
        guard !commandInFlight else { return }
        commandInFlight = true
        defer { commandInFlight = false }
        notice = nil
        commandStamp &+= 1
        beginSwitching()
        let outcome = await send(spotify)
        if outcome == .playing {
            // Spotify needs a moment to report the new song: ask at 0.8 s and again at 2 s.
            refreshSoon(after: 0.8)
            refreshSoon(after: 2)
        } else {
            endSwitching()
            finish(outcome)
        }
    }

    /// Maps a failed outcome to a notice; a started song is refreshed.
    private func finish(_ outcome: SpotifyClient.PlayOutcome) {
        switch outcome {
        case .playing: refreshSoon(after: 0.8)
        case .noDevice: notice = .noDevice
        case .notPremium: notice = .notPremium
        case let .failed(message): notice = .failed(message)
        }
    }

    private func beginSwitching() {
        switching = true
        switchingTask?.cancel()
        switchingTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            self?.switching = false
        }
    }

    private func endSwitching() {
        switchingTask?.cancel()
        switchingTask = nil
        switching = false
    }

    /// Forgets everything (Spotify was disconnected).
    func reset() {
        generation &+= 1
        commandStamp &+= 1
        state = .idle
        notice = nil
        endSwitching()
    }

    /// Assigns `new` only when something visible changes: the song, playing/paused, nothing ↔ something, or
    /// failed ↔ loaded. Progress alone never triggers a re-render.
    private func assign(_ new: LyricsLoad<SpotifyPlayback?>) {
        switch (state, new) {
        case let (.loaded(old), .loaded(fresh)):
            if switching, let o = old, let f = fresh, o.track.spotifyID != f.track.spotifyID { endSwitching() }
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
