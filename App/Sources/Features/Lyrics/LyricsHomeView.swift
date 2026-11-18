import MemoriseCore
import SwiftUI

/// The Lyrics tab: connect Spotify, pick a song, open the reader (PLAN_M6 L6).
struct LyricsHomeView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var model: LyricsHomeViewModel?

    var body: some View {
        Group {
            if let model {
                LyricsHomeContent(model: model)
            } else {
                Color.clear
            }
        }
        .onAppear {
            if model == nil { model = LyricsHomeViewModel(spotify: env.spotify, nowPlaying: env.nowPlaying) }
        }
    }
}

/// Restarts the now-playing poll when Spotify connects or disconnects, or the app goes to or from the foreground.
struct NowPlayingWatchKey: Hashable {
    let connected: Bool
    let active: Bool
}

private struct LyricsHomeContent: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.scenePhase) private var scenePhase
    @Bindable var model: LyricsHomeViewModel

    var body: some View {
        NavigationStack(path: $model.path) {
            ScrollView {
                LazyVStack(spacing: 16) {
                    switch env.spotify.state {
                    case .notConfigured:
                        NotConfiguredCard().appearAnimation()
                    case .disconnected, .connecting:
                        ConnectCard(
                            connecting: env.spotify.state == .connecting, error: model.connectError
                        ) { Task { await model.connect() } }
                            .appearAnimation()
                    case .connected:
                        connectedContent
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            }
            .scrollDismissesKeyboard(.interactively)
            .auroraBackground(colors: Subject.korean.colors, intensity: 0.8, running: model.path.isEmpty)
            // On the root, not the stack, so a pushed reader or playlist cancels the poll.
            .task(id: NowPlayingWatchKey(connected: env.spotify.isConnected, active: scenePhase == .active)) {
                guard env.spotify.isConnected, scenePhase == .active else { return }
                await env.nowPlaying.watch()
            }
            .navigationTitle("Lyrics")
            .navigationDestination(for: LyricsRoute.self) { route in
                switch route {
                case let .reader(track): LyricsReaderView(track: track) { model.showLyrics(for: $0) }
                case let .playlist(playlist): PlaylistTracksView(playlist: playlist, model: model)
                }
            }
            .refreshable { if env.spotify.isConnected { await model.refreshAll() } }
        }
        .task(id: env.spotify.isConnected) {
            if env.spotify.isConnected { await model.refreshAll() }
        }
        .onChange(of: env.spotify.isConnected) { _, connected in
            if !connected { model.reset() }
        }
    }

    // MARK: Connected

    @ViewBuilder private var connectedContent: some View {
        NowPlayingCard(model: model).appearAnimation()

        if let notice = model.notice {
            NoticeBanner(text: notice) { model.dismissNotice() }
        }

        SearchField(text: $model.query)
            .appearAnimation(index: 1)

        if model.isSearching {
            searchResults
        } else {
            Picker("Songs", selection: $model.source) {
                ForEach(LyricsSource.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("lyrics.source")
            .appearAnimation(index: 2)

            if let error = model.listError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("lyrics.listError")
            }

            sourceList
        }
    }

    @ViewBuilder private var searchResults: some View {
        Group {
            switch model.results {
            case .idle, .loading:
                LoadingRows()
            case let .failed(message):
                MessageCard(icon: "exclamationmark.triangle", title: "Search failed", message: message, retry: { Task { await model.runSearch() } })
            case let .loaded(tracks):
                if tracks.isEmpty {
                    MessageCard(icon: "magnifyingglass", title: "No songs found", message: "Try the title and the artist.")
                } else {
                    TrackList(tracks: tracks, model: model)
                }
            }
        }
        .task(id: model.query) {
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            await model.runSearch()
        }
    }

    @ViewBuilder private var sourceList: some View {
        Group {
            switch model.source {
            case .recent:
                listState(model.recent, empty: ("clock", "Nothing played yet", "Songs you play in Spotify show up here."),
                          reload: { await model.loadRecent(force: true) }) { TrackList(tracks: $0, model: model) }
            case .playlists:
                listState(model.playlists, empty: ("music.note.list", "No playlists", "Playlists you create or follow show up here."),
                          reload: { await model.loadPlaylists(force: true) }) { playlists in
                    VStack(spacing: 12) {
                        PlaylistList(playlists: playlists, model: model)
                        if model.playlistsNextOffset != nil {
                            LoadMoreRow(loading: model.loadingMorePlaylists, identifier: "lyricsLoadMorePlaylists") {
                                await model.loadMorePlaylists()
                            }
                        }
                    }
                }
            case .liked:
                listState(model.liked, empty: ("heart", "No liked songs", "Songs you like in Spotify show up here."),
                          reload: { await model.loadLiked(force: true) }) { tracks in
                    VStack(spacing: 12) {
                        TrackList(tracks: tracks, model: model)
                        if model.likedNextOffset != nil {
                            LoadMoreRow(loading: model.loadingMoreLiked, identifier: "lyrics.loadMore") {
                                await model.loadMoreLiked()
                            }
                        }
                    }
                }
            }
        }
        .task(id: model.source) { await model.loadSource() }
    }

    @ViewBuilder private func listState<V, Content: View>(
        _ load: LyricsLoad<[V]>, empty: (String, String, String), reload: @escaping () async -> Void,
        @ViewBuilder content: ([V]) -> Content
    ) -> some View {
        switch load {
        case .idle, .loading:
            LoadingRows()
        case let .failed(message):
            MessageCard(icon: "wifi.exclamationmark", title: "Couldn't load", message: message, retry: { Task { await reload() } })
        case let .loaded(items):
            if items.isEmpty {
                MessageCard(icon: empty.0, title: empty.1, message: empty.2)
            } else {
                content(items)
            }
        }
    }
}

// MARK: - Cards

private struct NotConfiguredCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Spotify isn't set up yet", systemImage: "gearshape.2")
                .font(.headline)
            Text("The Lyrics tab needs a Spotify app and a Genius token.")
                .font(.subheadline)
            VStack(alignment: .leading, spacing: 6) {
                Text("1. Follow “Lyrics setup” in the README.")
                Text("2. Put both keys in App/Config/Secrets.xcconfig.")
                Text("3. Build and run again.")
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .glassCard(tint: Theme.amber)
        .accessibilityIdentifier("lyrics.notConfigured")
    }
}

private struct ConnectCard: View {
    let connecting: Bool
    let error: String?
    let connect: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "music.note.list")
                .font(.system(size: 40, weight: .semibold))
                .foregroundStyle(Subject.korean.gradient)
            Text("Read the lyrics of what you listen to")
                .font(.title3.weight(.bold))
                .multilineTextAlignment(.center)
            Text("Connect Spotify, pick a song, then tap any word to see what it means and save it to a deck.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button(action: connect) {
                HStack {
                    if connecting { ProgressView().tint(.white) }
                    Text(connecting ? "Connecting…" : "Connect Spotify").fontWeight(.bold)
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 50)
                .background(Subject.korean.gradient, in: Capsule())
            }
            .buttonStyle(PressableStyle())
            .disabled(connecting)
            .accessibilityIdentifier("lyrics.connect")
            if let error, !error.isEmpty {
                Text(error).font(.footnote).foregroundStyle(.red).multilineTextAlignment(.center)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .glassCard(tint: Theme.pink)
    }
}

private struct NowPlayingCard: View {
    @Bindable var model: LyricsHomeViewModel

    var body: some View {
        Group {
            switch model.nowPlaying {
            case .idle, .loading:
                HStack(spacing: 12) {
                    ProgressView()
                    Text("Checking what's playing…").font(.subheadline).foregroundStyle(.secondary)
                    Spacer()
                }
            case let .failed(message):
                HStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle").foregroundStyle(Theme.amber)
                    Text(message).font(.subheadline).foregroundStyle(.secondary)
                    Spacer()
                    refreshButton
                }
            case let .loaded(playback):
                if let track = playback?.track {
                    HStack(spacing: 12) {
                        ArtworkView(url: track.artworkURL, size: 56)
                        VStack(alignment: .leading, spacing: 2) {
                            Label(playback?.isPlaying == false ? "Paused" : "Now playing",
                                  systemImage: playback?.isPlaying == false ? "pause.fill" : "waveform")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Theme.pink)
                            Text(track.displayTitle).font(.headline).lineLimit(1)
                            Text(track.artistLine).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer(minLength: 8)
                        refreshButton
                        Button("Open") { Task { await model.open(track, play: false) } }
                            .font(.subheadline.weight(.bold))
                            .padding(.horizontal, 16)
                            .frame(minHeight: 44)
                            .background(Subject.korean.gradient, in: Capsule())
                            .foregroundStyle(.white)
                            .buttonStyle(PressableStyle())
                            .accessibilityIdentifier("lyrics.nowPlaying.open")
                    }
                } else {
                    HStack(spacing: 12) {
                        Image(systemName: "pause.circle").font(.title2).foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Nothing playing").font(.headline)
                            Text("Start a song in Spotify, or pick one below.").font(.subheadline).foregroundStyle(.secondary)
                        }
                        Spacer()
                        refreshButton
                    }
                }
            }
        }
        .padding(16)
        .glassCard(tint: Theme.pink)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("lyrics.nowPlaying")
    }

    private var refreshButton: some View {
        Button {
            Task { await model.refreshNowPlaying() }
        } label: {
            Image(systemName: "arrow.clockwise")
                .font(.system(size: 15, weight: .bold))
                .frame(width: 44, height: 44)
        }
        .buttonStyle(PressableStyle(scale: 0.88))
        .accessibilityLabel("Refresh now playing")
        .accessibilityIdentifier("lyrics.nowPlaying.refresh")
    }
}

private struct NoticeBanner: View {
    let text: String
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "info.circle.fill").foregroundStyle(Theme.amber)
            Text(text).font(.footnote)
            Spacer(minLength: 4)
            Button(action: dismiss) { Image(systemName: "xmark").font(.footnote.weight(.bold)) }
                .frame(width: 44, height: 44)
                .accessibilityLabel("Dismiss")
        }
        .padding(.leading, 14)
        .glassCard(radius: Theme.smallRadius, tint: Theme.amber)
        .transition(.opacity.combined(with: .move(edge: .top)))
        .accessibilityIdentifier("lyrics.notice")
    }
}

private struct SearchField: View {
    @Binding var text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search songs", text: $text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .accessibilityIdentifier("lyrics.search")
            if !text.isEmpty {
                Button { text = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                    .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 44)
        .glassCard(radius: Theme.smallRadius)
    }
}

// MARK: - Lists

private struct TrackRow: View {
    let track: TrackInfo

    var body: some View {
        HStack(spacing: 12) {
            ArtworkView(url: track.artworkURL)
            VStack(alignment: .leading, spacing: 2) {
                Text(track.displayTitle).font(.body.weight(.semibold)).lineLimit(1)
                Text(track.artistLine).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right").font(.footnote.weight(.bold)).foregroundStyle(.tertiary)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .frame(minHeight: 60)
        .contentShape(Rectangle())
    }
}

struct TrackList: View {
    let tracks: [TrackInfo]
    @Bindable var model: LyricsHomeViewModel

    var body: some View {
        LazyVStack(spacing: 0) {
            ForEach(tracks.indices, id: \.self) { index in
                let track = tracks[index]
                Button {
                    Task { await model.open(track, play: true) }
                } label: {
                    TrackRow(track: track)
                }
                .buttonStyle(PressableStyle(scale: 0.98))
                .accessibilityIdentifier("lyrics.row.\(track.spotifyID)")
                if index < tracks.count - 1 { Divider().padding(.leading, 68) }
            }
        }
        .glassCard(radius: Theme.smallRadius)
    }
}

private struct PlaylistList: View {
    let playlists: [SpotifyPlaylist]
    @Bindable var model: LyricsHomeViewModel

    var body: some View {
        LazyVStack(spacing: 0) {
            ForEach(Array(playlists.enumerated()), id: \.element.id) { index, playlist in
                Button {
                    model.path.append(.playlist(playlist))
                } label: {
                    HStack(spacing: 12) {
                        ArtworkView(url: playlist.artworkURL)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(playlist.name).font(.body.weight(.semibold)).lineLimit(1)
                            if !model.canReadItems(of: playlist) {
                                Label("Not shared by Spotify", systemImage: "lock.fill")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Spacer(minLength: 8)
                        Image(systemName: "chevron.right").font(.footnote.weight(.bold)).foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
                    .frame(minHeight: 60)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressableStyle(scale: 0.98))
                .accessibilityIdentifier("lyrics.playlist.\(playlist.id)")
                if index < playlists.count - 1 { Divider().padding(.leading, 68) }
            }
        }
        .glassCard(radius: Theme.smallRadius)
    }
}

/// Songs of one playlist.
private struct PlaylistTracksView: View {
    let playlist: SpotifyPlaylist
    @Bindable var model: LyricsHomeViewModel
    @State private var load: LyricsLoad<PlaylistContents> = .idle

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                switch load {
                case .idle, .loading:
                    LoadingRows()
                case let .failed(message):
                    MessageCard(icon: "wifi.exclamationmark", title: "Couldn't load", message: message, retry: { Task { await fetch() } })
                case let .loaded(contents):
                    switch contents {
                    case .notShared:
                        MessageCard(
                            icon: "lock.fill", title: "Not shared by Spotify",
                            message: "Spotify only shares songs from playlists you own.")
                            .accessibilityIdentifier("lyrics.playlist.notShared")
                    case .tracks:
                        if model.playlistTracks.isEmpty {
                            MessageCard(icon: "music.note", title: "Empty playlist", message: "There are no songs in this playlist.")
                        } else {
                            TrackList(tracks: model.playlistTracks, model: model)
                            if model.itemsNextOffset != nil {
                                LoadMoreRow(loading: model.loadingMoreItems, identifier: "lyricsLoadMoreItems") {
                                    await model.loadMoreItems()
                                }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .auroraBackground(colors: Subject.korean.colors, intensity: 0.8, running: model.path.last == .playlist(playlist))
        .navigationTitle(playlist.name)
        .navigationBarTitleDisplayMode(.inline)
        .task { await fetch() }
    }

    private func fetch() async {
        load = .loading
        do {
            load = .loaded(try await model.playlistItems(id: playlist.id))
        } catch is CancellationError {
            load = .idle
        } catch {
            load = .failed(LyricsHomeViewModel.message(error))
        }
    }
}

// MARK: - States

/// "Load more" at the end of a paged list. Loads on appear (the model guards against double loads); tapping retries.
private struct LoadMoreRow: View {
    let loading: Bool
    let identifier: String
    let load: () async -> Void

    var body: some View {
        Button {
            Task { await load() }
        } label: {
            if loading { ProgressView() } else { Text("Load more").fontWeight(.semibold) }
        }
        .frame(maxWidth: .infinity, minHeight: 44)
        .buttonStyle(PressableStyle())
        .accessibilityIdentifier(identifier)
        .onAppear { Task { await load() } }
    }
}

private struct LoadingRows: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false

    var body: some View {
        VStack(spacing: 0) {
            ForEach(0..<5, id: \.self) { _ in
                HStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: 9, style: .continuous).fill(.primary.opacity(0.1)).frame(width: 44, height: 44)
                    VStack(alignment: .leading, spacing: 6) {
                        Capsule().fill(.primary.opacity(0.1)).frame(width: 150, height: 12)
                        Capsule().fill(.primary.opacity(0.07)).frame(width: 90, height: 10)
                    }
                    Spacer()
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .frame(minHeight: 60)
            }
        }
        .glassCard(radius: Theme.smallRadius)
        .opacity(pulse ? 0.55 : 1)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { pulse = true }
        }
        .accessibilityElement()
        .accessibilityLabel("Loading")
    }
}

private struct MessageCard: View {
    let icon: String
    let title: String
    let message: String
    var retry: (() -> Void)?

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon).font(.title).foregroundStyle(.secondary)
            Text(title).font(.headline)
            Text(message).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            if let retry {
                Button("Try again", action: retry)
                    .font(.subheadline.weight(.semibold))
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("lyrics.retry")
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .glassCard(radius: Theme.smallRadius)
    }
}

// MARK: - Previews

#Preview("Not configured") {
    LyricsHomeView()
        .environment(AppEnvironment.preview())
}

#Preview("Connect") {
    NavigationStack {
        ScrollView { ConnectCard(connecting: false, error: nil) {}.padding() }
            .auroraBackground(colors: Subject.korean.colors)
    }
}

#Preview("Rows") {
    let tracks = [
        TrackInfo(spotifyID: "1", title: "Spring Day", titleKo: "봄날", artists: ["BTS"]),
        TrackInfo(spotifyID: "2", title: "Supernova", artists: ["aespa"]),
    ]
    let spotify = SpotifyClient(initialState: .connected(displayName: "me"))
    let model = LyricsHomeViewModel(spotify: spotify, nowPlaying: NowPlayingMonitor(spotify: spotify))
    return ScrollView { TrackList(tracks: tracks, model: model).padding() }
        .auroraBackground(colors: Subject.korean.colors)
}

#Preview("Paused") {
    let track = TrackInfo(spotifyID: "1", title: "Spring Day", titleKo: "봄날", artists: ["BTS"])
    let spotify = SpotifyClient(initialState: .connected(displayName: "me"))
    let monitor = NowPlayingMonitor(spotify: spotify)
    let model = LyricsHomeViewModel(spotify: spotify, nowPlaying: monitor)
    monitor.previewNowPlaying(SpotifyPlayback(track: track, isPlaying: false))
    return ScrollView { NowPlayingCard(model: model).padding() }
        .auroraBackground(colors: Subject.korean.colors)
}
