import MemoriseCore
import SwiftUI
@preconcurrency import Translation

/// Reads one song: Hangul page, swipe left for the English page (PLAN_M6 L7).
struct LyricsReaderView: View {
    @Environment(AppEnvironment.self) private var env
    let track: TrackInfo
    let onShowLyrics: (TrackInfo) -> Void
    @State private var model: LyricsReaderViewModel?

    var body: some View {
        Group {
            if let model {
                ReaderContent(model: model, onShowLyrics: onShowLyrics)
            } else {
                Color.clear
            }
        }
        .onAppear {
            if model == nil {
                model = LyricsReaderViewModel(track: track, lyrics: env.lyrics, spotify: env.spotify, glosses: env.glosses)
            }
        }
    }
}

private struct ReaderContent: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Bindable var model: LyricsReaderViewModel
    let onShowLyrics: (TrackInfo) -> Void
    @State private var page = 0

    /// What Spotify plays right now, when connected and known.
    private var playback: SpotifyPlayback? {
        guard env.spotify.isConnected else { return nil }
        return env.nowPlaying.state.value ?? nil
    }

    /// Spotify plays the open song: shows the header chip.
    private var playingHere: SpotifyPlayback? { playback.flatMap { model.isShowing($0) ? $0 : nil } }

    /// Spotify plays another song: shows the bottom bar.
    private var playingElsewhere: SpotifyPlayback? { playback.flatMap { model.isShowing($0) ? nil : $0 } }

    var body: some View {
        VStack(spacing: 0) {
            header
            switch model.phase {
            case .loading:
                SkeletonLines()
            case .ready:
                pages
            case .notAvailable:
                StateMessage(
                    icon: "music.note.slash", title: "Lyrics not available for this track",
                    message: nil, action: "Try again"
                ) { Task { await model.load(force: true) } }
                    .accessibilityIdentifier("lyrics.notAvailable")
            case .offline:
                StateMessage(
                    icon: "wifi.slash", title: "You're offline",
                    message: "Lyrics you've opened before still work.", action: "Retry"
                ) { Task { await model.load() } }
                    .accessibilityIdentifier("lyrics.offline")
            case let .failed(message):
                StateMessage(icon: "exclamationmark.triangle", title: "Couldn't load lyrics", message: message, action: "Retry") {
                    Task { await model.load() }
                }
            }
        }
        .auroraBackground(colors: Subject.korean.colors, intensity: 0.6, animated: false)
        .navigationTitle(model.track.displayTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .overlay(alignment: .bottom) {
            if let toast = model.toast {
                Text(toast)
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                    .background(.regularMaterial, in: Capsule())
                    .overlay(Capsule().strokeBorder(.white.opacity(0.25)))
                    .padding(.bottom, 24)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .accessibilityIdentifier("lyrics.toast")
            }
        }
        .animation(Theme.spring, value: model.toast)
        // After the overlay, so the toast sits above the bar instead of under it.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let other = playingElsewhere {
                ReaderNowPlayingBar(playback: other) { onShowLyrics(other.track) }
                    .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(reduceMotion ? .easeInOut(duration: 0.2) : Theme.spring, value: playingElsewhere)
        // The home root stops its poll while the reader is on top, so the reader runs its own.
        .task(id: NowPlayingWatchKey(connected: env.spotify.isConnected, active: scenePhase == .active)) {
            guard env.spotify.isConnected, scenePhase == .active else { return }
            await env.nowPlaying.watch()
        }
        .task { await model.load() }
        .onChange(of: env.dataVersion) { _, _ in model.tokenise() }
        .translationTask(model.translation) { session in
            await env.glosses.runBatch(session: session, track: model.trackID)
        }
        .sheet(item: $model.adding) { candidate in
            AddToDeckSheet(candidate: candidate) { deckTitle in
                model.showToast("Added to \(deckTitle)")
            }
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(spacing: 10) {
            VStack(spacing: 2) {
                Text(model.track.title).font(.headline).lineLimit(1)
                if let ko = model.track.titleKo {
                    Text(ko).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                }
                Text(model.track.artistLine).font(.footnote).foregroundStyle(.secondary).lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .combine)

            if let here = playingHere {
                ReaderPlayingChip(isPlaying: here.isPlaying)
                    .transition(.opacity)
            }

            if model.isAvailable {
                PageIndicator(page: $page)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }

    // MARK: Pages

    private var pages: some View {
        TabView(selection: $page) {
            KoreanLyricsPage(model: model).tag(0)
            EnglishLyricsPage(model: model).tag(1)
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .animation(Theme.softSpring, value: page)
    }
}

// MARK: - Pieces

/// "한국어 | English", mirrors the swipe.
private struct PageIndicator: View {
    @Binding var page: Int
    private let titles = ["한국어", "English"]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(titles.indices, id: \.self) { i in
                Button {
                    page = i
                } label: {
                    Text(titles[i])
                        .font(.footnote.weight(.semibold))
                        .padding(.horizontal, 16)
                        .frame(minHeight: 32)
                        .background {
                            if page == i { Capsule().fill(Subject.korean.gradient) }
                        }
                        .foregroundStyle(page == i ? Color.white : Color.primary)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(page == i ? .isSelected : [])
                .accessibilityIdentifier("lyrics.page.\(i)")
            }
        }
        .padding(3)
        .background(.thinMaterial, in: Capsule())
        .animation(Theme.spring, value: page)
    }
}

private struct SkeletonLines: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false
    private let widths: [CGFloat] = [0.8, 0.6, 0.9, 0.5, 0.7, 0.85, 0.55, 0.75]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            ForEach(widths.indices, id: \.self) { i in
                GeometryReader { geo in
                    Capsule().fill(.primary.opacity(0.1)).frame(width: geo.size.width * widths[i], height: 18)
                }
                .frame(height: 18)
            }
            Spacer()
        }
        .padding(20)
        .opacity(pulse ? 0.5 : 1)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { pulse = true }
        }
        .accessibilityElement()
        .accessibilityLabel("Loading lyrics")
        .accessibilityIdentifier("lyrics.loading")
    }
}

private struct StateMessage: View {
    let icon: String
    let title: String
    let message: String?
    let action: String
    let run: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 44)).foregroundStyle(.secondary)
            Text(title).font(.title3.weight(.semibold)).multilineTextAlignment(.center)
            if let message {
                Text(message).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            Button(action: run) {
                Text(action).font(.subheadline.weight(.semibold)).padding(.horizontal, 20).frame(minHeight: 44)
            }
            .buttonStyle(PressableStyle())
            .accessibilityIdentifier("lyrics.retry")
        }
        .padding(32)
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
        .frame(maxHeight: .infinity, alignment: .top)
    }
}

#Preview("Reader") {
    NavigationStack {
        LyricsReaderView(track: TrackInfo(spotifyID: "x", title: "Spring Day", titleKo: "봄날", artists: ["BTS"])) { _ in }
    }
    .environment(AppEnvironment.preview())
}

#if DEBUG
@MainActor private func readerPreview(playing: SpotifyPlayback) -> some View {
    let env = AppEnvironment.preview()
    env.nowPlaying.previewNowPlaying(playing)
    return NavigationStack {
        LyricsReaderView(track: TrackInfo(spotifyID: "x", title: "Spring Day", titleKo: "봄날", artists: ["BTS"])) { _ in }
    }
    .environment(env)
}

#Preview("Reader · same song (chip)") {
    readerPreview(playing: SpotifyPlayback(
        track: TrackInfo(spotifyID: "x", title: "Spring Day", artists: ["BTS"]), isPlaying: true))
}

#Preview("Reader · other song (bar)") {
    readerPreview(playing: SpotifyPlayback(
        track: TrackInfo(spotifyID: "y", title: "Dynamite", artists: ["BTS"]), isPlaying: false))
}
#endif
