import MemoriseCore
import SwiftUI

/// "Spotify is playing another song": a bottom bar with a Show lyrics button (PLAN_R10 P-6). It never changes
/// playback and never switches the reader by itself.
struct ReaderNowPlayingBar: View {
    let playback: SpotifyPlayback
    let onShow: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            ArtworkView(url: playback.track.artworkURL, size: 40)
            VStack(alignment: .leading, spacing: 1) {
                Text(playback.isPlaying ? "Now playing" : "Paused")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Theme.pink)
                Text(playback.track.displayTitle).font(.subheadline.weight(.semibold)).lineLimit(1)
                Text(playback.track.artistLine).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 8)
            Button(action: onShow) {
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
        .padding(.vertical, 8)
        .padding(.leading, 12)
        .padding(.trailing, 8)
        .glassCard(radius: 28)
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("lyrics.reader.nowPlayingBar")
    }
}

/// "▶ Playing" / "⏸ Paused" under the artist line when Spotify plays the open song.
struct ReaderPlayingChip: View {
    let isPlaying: Bool

    var body: some View {
        Label(isPlaying ? "Playing" : "Paused", systemImage: isPlaying ? "waveform" : "pause.fill")
            .font(.caption.weight(.semibold))
            .foregroundStyle(Theme.pink)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Theme.pink.opacity(0.14), in: Capsule())
            .accessibilityIdentifier("lyrics.reader.playingChip")
    }
}

#if DEBUG
private let previewPlayback = SpotifyPlayback(
    track: TrackInfo(spotifyID: "n", title: "Dynamite", titleKo: nil, artists: ["BTS"]), isPlaying: true)

#Preview("Bar playing") {
    VStack {
        Spacer()
        ReaderNowPlayingBar(playback: previewPlayback, onShow: {})
    }
    .auroraBackground(colors: Subject.korean.colors, animated: false)
}

#Preview("Bar paused") {
    VStack {
        Spacer()
        ReaderNowPlayingBar(playback: SpotifyPlayback(track: previewPlayback.track, isPlaying: false), onShow: {})
    }
    .auroraBackground(colors: Subject.korean.colors, animated: false)
}

#Preview("Chip") {
    HStack { ReaderPlayingChip(isPlaying: true); ReaderPlayingChip(isPlaying: false) }.padding()
}
#endif
