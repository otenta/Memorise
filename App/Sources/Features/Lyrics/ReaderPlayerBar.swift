import MemoriseCore
import SwiftUI

/// The reader's bottom player bar (PLAN_R12 P-12). What it shows depends on what Spotify is doing:
/// the open song (controls), another song (play/pause and Show lyrics, never auto-follow), or nothing (Play this song).
struct ReaderPlayerBar: View {
    /// What Spotify plays; `nil` when nothing is.
    let playback: SpotifyPlayback?
    /// `playback` is the song open in the reader.
    let isHere: Bool
    let player: NowPlayingMonitor
    let onShowLyrics: (TrackInfo) -> Void
    let onPlayThis: () -> Void

    var body: some View {
        Group {
            if let playback {
                if isHere { here(playback) } else { elsewhere(playback) }
            } else {
                nothing
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .glassCard(radius: 28)
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("lyrics.reader.nowPlayingBar")
    }

    // MARK: States

    private func here(_ playback: SpotifyPlayback) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                caption(for: playback)
                Text(playback.track.displayTitle).font(.subheadline.weight(.semibold)).lineLimit(1)
            }
            Spacer(minLength: 4)
            PlayerControls(
                isPlaying: playback.isPlaying, disabled: player.commandInFlight, switching: player.switching,
                onPrevious: { Task { await player.skipPrevious() } },
                onToggle: { Task { await player.togglePlayPause() } },
                onNext: { Task { await player.skipNext() } })
        }
    }

    private func elsewhere(_ playback: SpotifyPlayback) -> some View {
        HStack(spacing: 10) {
            ArtworkView(url: playback.track.artworkURL, size: 40)
            VStack(alignment: .leading, spacing: 1) {
                caption(for: playback)
                Text(playback.track.displayTitle).font(.subheadline.weight(.semibold)).lineLimit(1)
                Text(playback.track.artistLine).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 4)
            PlayerControls(
                isPlaying: playback.isPlaying, disabled: player.commandInFlight, showsSkip: false,
                onPrevious: {}, onToggle: { Task { await player.togglePlayPause() } }, onNext: {})
                .scaleEffect(0.85)
                .frame(width: 46, height: 46)
            Button { onShowLyrics(playback.track) } label: {
                Text("Show lyrics")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .frame(minHeight: 44)
                    .background(Subject.korean.gradient, in: Capsule())
            }
            .buttonStyle(PressableStyle())
            .accessibilityIdentifier("lyrics.reader.showNowPlaying")
        }
    }

    private var nothing: some View {
        Button(action: onPlayThis) {
            Label("Play this song", systemImage: "play.fill")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(Subject.korean.gradient, in: Capsule())
                .opacity(player.commandInFlight ? 0.7 : 1)
        }
        .buttonStyle(PressableStyle())
        .disabled(player.commandInFlight)
        .accessibilityIdentifier("lyrics.player.playThis")
    }

    @ViewBuilder private func caption(for playback: SpotifyPlayback) -> some View {
        if player.switching {
            ProgressView().controlSize(.mini)
        } else {
            Text(playback.isPlaying ? "Now playing" : "Paused")
                .font(.caption2.weight(.bold))
                .foregroundStyle(Theme.pink)
        }
    }
}

#if DEBUG
@MainActor private func playerBarPreview(_ playback: SpotifyPlayback?, here: Bool) -> some View {
    let monitor = NowPlayingMonitor(spotify: SpotifyClient(initialState: .connected(displayName: "me")))
    return VStack {
        Spacer()
        ReaderPlayerBar(playback: playback, isHere: here, player: monitor, onShowLyrics: { _ in }, onPlayThis: {})
    }
    .auroraBackground(colors: Subject.korean.colors, animated: false)
}

private let previewTrack = TrackInfo(spotifyID: "n", title: "Dynamite", artists: ["BTS"])

#Preview("Bar · this song playing") { playerBarPreview(SpotifyPlayback(track: previewTrack, isPlaying: true), here: true) }

#Preview("Bar · this song paused") { playerBarPreview(SpotifyPlayback(track: previewTrack, isPlaying: false), here: true) }

#Preview("Bar · another song") { playerBarPreview(SpotifyPlayback(track: previewTrack, isPlaying: true), here: false) }

#Preview("Bar · nothing playing") { playerBarPreview(nil, here: false) }
#endif
