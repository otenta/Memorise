import MemoriseCore
import SwiftUI

/// Previous · play/pause · next (PLAN_R12 P-11). The caller decides which actions run.
struct PlayerControls: View {
    let isPlaying: Bool
    /// A command is running: taps are ignored by the monitor, and the buttons dim.
    let disabled: Bool
    var showsSkip = true
    /// After next or previous: the skip glyphs dim until the new song shows.
    var switching = false
    let onPrevious: () -> Void
    let onToggle: () -> Void
    let onNext: () -> Void

    @State private var taps = 0

    var body: some View {
        HStack(spacing: showsSkip ? 18 : 0) {
            if showsSkip {
                skip("backward.fill", label: "Previous", id: "lyrics.player.previous", action: onPrevious)
            }
            Button {
                taps += 1
                onToggle()
            } label: {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.white)
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 52, height: 52)
                    .background(Subject.korean.gradient, in: Circle())
                    .opacity(disabled ? 0.7 : 1)
            }
            .buttonStyle(PressableStyle(scale: 0.9))
            .accessibilityLabel(isPlaying ? "Pause" : "Play")
            .accessibilityIdentifier("lyrics.player.toggle")
            if showsSkip {
                skip("forward.fill", label: "Next", id: "lyrics.player.next", action: onNext)
            }
        }
        .sensoryFeedback(.impact(weight: .light), trigger: taps)
        .animation(.easeOut(duration: 0.15), value: isPlaying)
    }

    private func skip(_ symbol: String, label: String, id: String, action: @escaping () -> Void) -> some View {
        Button {
            taps += 1
            action()
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.primary)
                .opacity(switching || disabled ? 0.35 : 1)
                .frame(width: 48, height: 48)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle(scale: 0.88))
        .accessibilityLabel(label)
        .accessibilityIdentifier(id)
    }
}

/// Why a player command didn't work, with Open Spotify for the no-device case (PLAN_R12 P-10).
struct PlayerNoticeBanner: View {
    let notice: PlayerNotice
    let onOpenSpotify: () -> Void
    let dismiss: () -> Void

    private var text: String {
        switch notice {
        case .noDevice: "Spotify isn't open on any device. Open it once, then tap ▶ here."
        case .notPremium: "Spotify needs Premium to control playback from here."
        case let .failed(message): message
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "info.circle.fill").foregroundStyle(Theme.amber)
            VStack(alignment: .leading, spacing: 6) {
                Text(text).font(.footnote).fixedSize(horizontal: false, vertical: true)
                if notice == .noDevice {
                    Button("Open Spotify", action: onOpenSpotify)
                        .font(.footnote.weight(.bold))
                        .buttonStyle(PressableStyle())
                        .accessibilityIdentifier("lyrics.player.openSpotify")
                }
            }
            Spacer(minLength: 4)
            Button(action: dismiss) { Image(systemName: "xmark").font(.footnote.weight(.bold)) }
                .frame(width: 44, height: 44)
                .accessibilityLabel("Dismiss")
        }
        .padding(.leading, 14)
        .padding(.vertical, 4)
        .glassCard(radius: Theme.smallRadius, tint: Theme.amber)
        .transition(.opacity.combined(with: .move(edge: .top)))
        .accessibilityIdentifier("lyrics.player.notice")
    }
}

#Preview("Controls") {
    VStack(spacing: 24) {
        PlayerControls(isPlaying: true, disabled: false, onPrevious: {}, onToggle: {}, onNext: {})
        PlayerControls(isPlaying: false, disabled: false, onPrevious: {}, onToggle: {}, onNext: {})
        PlayerControls(isPlaying: true, disabled: true, switching: true, onPrevious: {}, onToggle: {}, onNext: {})
        PlayerControls(isPlaying: true, disabled: false, showsSkip: false, onPrevious: {}, onToggle: {}, onNext: {})
    }
    .padding()
}

#Preview("Notices") {
    VStack(spacing: 12) {
        PlayerNoticeBanner(notice: .noDevice, onOpenSpotify: {}, dismiss: {})
        PlayerNoticeBanner(notice: .notPremium, onOpenSpotify: {}, dismiss: {})
        PlayerNoticeBanner(notice: .failed("Couldn't reach Spotify."), onOpenSpotify: {}, dismiss: {})
    }
    .padding()
}
