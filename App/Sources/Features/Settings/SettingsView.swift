import MemoriseCore
import SwiftUI

/// Settings tab (§11.7).
struct SettingsView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var exportURLs: [URL] = []
    @State private var exporting = false
    @State private var exportError: String?
    @State private var resetTarget: ResetTarget?
    /// M5 K4: after reset-all, asked separately when the user has snippets.
    @State private var askDeleteSnippets = false
    /// M6: confirms the lyrics cache was cleared.
    @State private var clearedLyricsCache = false
    #if DEBUG && targetEnvironment(simulator)
    @State private var seeding = false
    #endif

    private enum ResetTarget: Identifiable {
        case deck(DeckID, String)
        case all

        var id: String {
            switch self {
            case let .deck(id, _): id.raw
            case .all: "*"
            }
        }

        var title: String {
            switch self {
            case let .deck(_, title): "Reset stats for \(title)?"
            case .all: "Reset all stats?"
            }
        }
    }

    var body: some View {
        @Bindable var s = env.settings
        NavigationStack {
            Form {
                Section {
                    Picker(selection: $s.noteNaming) {
                        Text("Letter (A)").tag(NoteNaming.letter)
                        Text("Solfège (La)").tag(NoteNaming.solfege)
                        Text("Both (A (La))").tag(NoteNaming.both)
                    } label: { SettingLabel("Note names", icon: "music.note", colors: Subject.music.colors) }
                    Picker(selection: $s.solfegeVariant) {
                        Text("Si").tag(SolfegeVariant.si)
                        Text("Ti").tag(SolfegeVariant.ti)
                    } label: { SettingLabel("Seventh degree", icon: "7.circle.fill", colors: [Theme.violet, Theme.pink]) }
                    Toggle(isOn: $s.leftHanded) { SettingLabel("Left-handed", icon: "hand.raised.fill", colors: [Theme.amber, .orange]) }
                    Picker(selection: $s.highEOnTop) {
                        Text("High E on top (tab)").tag(true)
                        Text("Low E on top").tag(false)
                    } label: { SettingLabel("String order", icon: "line.3.horizontal", colors: [Theme.teal, Theme.indigo]) }
                    Picker(selection: $s.defaultMaxFret) {
                        ForEach(FretboardOptions.maxFretPresets, id: \.self) { Text("\($0)").tag($0) }
                    } label: { SettingLabel("Max fret for new setups", icon: "ruler.fill", colors: [Theme.indigo, Theme.teal]) }
                    Toggle(isOn: $s.showStringHint) { SettingLabel("Show string hint (low E…)", icon: "lightbulb.fill", colors: [Theme.amber, Theme.coral]) }
                    Toggle(isOn: $s.playNoteOnReveal) { SettingLabel("Play note on reveal", icon: "music.note", colors: Subject.music.colors) }
                    Picker(selection: $s.dotLabels) {
                        Text("Notes").tag(DotLabels.notes)
                        Text("Degrees").tag(DotLabels.degrees)
                    } label: { SettingLabel("Dot labels (scales, chords)", icon: "circle.grid.3x3.fill", colors: [Theme.violet, Theme.indigo]) }
                    .accessibilityIdentifier("dotLabelsPicker")
                    Toggle(isOn: $s.showShapeHint) { SettingLabel("Show chord shape hint", icon: "hand.point.up.left.fill", colors: [Theme.teal, Theme.mint]) }
                        .accessibilityIdentifier("showShapeHintToggle")
                    Toggle(isOn: $s.spokenMicFeedback) { SettingLabel("Say Correct / Try again", icon: "mic.badge.plus", colors: [Theme.mint, Theme.teal]) }
                        .accessibilityIdentifier("spokenMicFeedbackToggle")
                    VStack(alignment: .leading) {
                        SettingLabel("Note volume", icon: "speaker.wave.3.fill", colors: Subject.music.colors)
                        Slider(value: $s.noteVolume, in: 0...1) {
                            Text("Note volume")
                        } minimumValueLabel: {
                            Image(systemName: "speaker.fill")
                        } maximumValueLabel: {
                            Image(systemName: "speaker.wave.3.fill")
                        } onEditingChanged: { editing in
                            if !editing { env.notePlayer.play(midi: 57) }
                        }
                    }
                } header: {
                    Text("Music")
                } footer: {
                    Text("Decks you've already practised keep their last settings.")
                }

                Section("Korean") {
                    Toggle(isOn: $s.autoPlayPronunciation) { SettingLabel("Auto-play pronunciation", icon: "speaker.wave.2.fill", colors: Subject.korean.colors) }
                    VStack(alignment: .leading, spacing: 10) {
                        SettingLabel("Speech rate", icon: "metronome.fill", colors: [Theme.pink, Theme.violet])
                        Slider(value: $s.speechRate, in: 0.2...0.6) {
                            Text("Speech rate")
                        } minimumValueLabel: {
                            Image(systemName: "tortoise.fill").foregroundStyle(.secondary)
                        } maximumValueLabel: {
                            Image(systemName: "hare.fill").foregroundStyle(.secondary)
                        }
                        .tint(Theme.pink)
                    }
                    .padding(.vertical, 4)
                    Button { env.speech.speak("안녕하세요", rate: s.speechRate) } label: {
                        HStack {
                            SettingLabel("Test voice", icon: "waveform", colors: [Theme.coral, Theme.amber])
                            Spacer()
                            Text("안녕하세요").font(.subheadline.weight(.semibold)).foregroundStyle(Subject.korean.gradient)
                        }
                    }
                    .foregroundStyle(.primary)
                    Toggle(isOn: $s.showRomanization) { SettingLabel("Show romanization on reveal", icon: "character.textbox", colors: [Theme.violet, Theme.pink]) }
                    if !env.speech.hasKoreanVoice {
                        Text("No Korean voice installed. Add one in Settings → Accessibility → Spoken Content → Voices → Korean.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }

                Section("Session") {
                    Toggle(isOn: $s.tapAnywhereForOK) { SettingLabel("Tap anywhere to reveal", icon: "hand.tap.fill", colors: [Theme.indigo, Theme.violet]) }
                    Toggle(isOn: $s.showTimer) { SettingLabel("Show timer during prompt", icon: "stopwatch.fill", colors: [Theme.amber, .orange]) }
                    Toggle(isOn: $s.hapticsEnabled) { SettingLabel("Haptics", icon: "iphone.radiowaves.left.and.right", colors: [Theme.mint, Theme.teal]) }
                    Toggle(isOn: $s.autoAdvanceOnCorrect) { SettingLabel("Auto-advance typed/choice answers", icon: "forward.fill", colors: [Theme.teal, Theme.indigo]) }
                        .accessibilityIdentifier("autoAdvanceToggle")
                }

                Section {
                    if exportURLs.isEmpty {
                        Button {
                            Task { await prepareExport() }
                        } label: {
                            HStack {
                                SettingLabel("Export data", icon: "tray.and.arrow.up.fill", colors: [Theme.teal, Theme.mint])
                                if exporting { Spacer(); ProgressView() }
                            }
                        }
                        .foregroundStyle(.primary)
                        .disabled(exporting)
                        .accessibilityIdentifier("exportButton")
                    } else {
                        ShareLink(items: exportURLs) {
                            SettingLabel("Share export (JSON + CSV)", icon: "square.and.arrow.up.fill", colors: [Theme.mint, Theme.teal])
                        }
                        .foregroundStyle(.primary)
                        .transition(.scale(scale: 0.9).combined(with: .opacity))
                    }
                    if let exportError {
                        Text(exportError).font(.footnote).foregroundStyle(.red)
                    }
                    Menu {
                        ForEach(env.catalog.decks, id: \.id) { deck in
                            Button(deck.title, role: .destructive) { resetTarget = .deck(deck.id, deck.title) }
                        }
                        Divider()
                        Button("All decks", role: .destructive) { resetTarget = .all }
                    } label: {
                        SettingLabel("Reset stats…", icon: "arrow.counterclockwise", colors: [Theme.rose, Theme.coral])
                    }
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("resetMenu")
                } header: {
                    Text("Data")
                } footer: {
                    Text("Export includes every session, attempt and item statistic.")
                }

                if env.spotify.state != .notConfigured {
                    Section {
                        if env.spotify.isConnected {
                            Button(role: .destructive) {
                                env.spotify.disconnect()
                            } label: {
                                SettingLabel("Disconnect Spotify", icon: "person.crop.circle.badge.xmark", colors: [Theme.rose, Theme.coral])
                            }
                            .foregroundStyle(.red)
                            .accessibilityIdentifier("lyrics.disconnect")
                        }
                        Button(role: .destructive) {
                            Task {
                                await env.lyrics.cache.clearAll()
                                env.glosses.clearAll()
                                clearedLyricsCache = true
                            }
                        } label: {
                            SettingLabel("Clear lyrics cache", icon: "trash.fill", colors: [Theme.indigo, Theme.violet])
                        }
                        .foregroundStyle(.red)
                        .accessibilityIdentifier("lyrics.clearCache")
                    } header: {
                        Text("Lyrics")
                    } footer: {
                        Text(clearedLyricsCache
                            ? "Lyrics cache cleared."
                            : "Lyrics are fetched when you open a song and kept on this device only. They are never exported.")
                    }
                }

                #if DEBUG && targetEnvironment(simulator)
                Section("Developer") {
                    Button {
                        seeding = true
                        Task {
                            do {
                                try await DevSeeder.seedYear(store: env.store)
                            } catch {
                                AppEnvironment.log.error("Seed failed: \(error.localizedDescription, privacy: .public)")
                            }
                            seeding = false
                            env.dataDidChange()
                        }
                    } label: {
                        HStack {
                            SettingLabel(seeding ? "Seeding…" : "Seed 1 year of synthetic history", icon: "hammer.fill", colors: [.gray, .secondary])
                            if seeding { Spacer(); ProgressView() }
                        }
                    }
                    .foregroundStyle(.primary)
                    .disabled(seeding)
                }
                #endif

                Section {
                    aboutCard
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }
            }
            .scrollContentBackground(.hidden)
            .auroraBackground(colors: [Theme.violet, Theme.teal], intensity: 0.6)
            .animation(Theme.spring, value: exportURLs)
            .navigationTitle("Settings")
            .onChange(of: env.dataVersion) { exportURLs = [] }
            .confirmationDialog(resetTarget?.title ?? "", isPresented: Binding(
                get: { resetTarget != nil },
                set: { if !$0 { resetTarget = nil } }
            ), titleVisibility: .visible, presenting: resetTarget) { target in
                Button("Reset", role: .destructive) { Task { await reset(target) } }
            } message: { _ in
                Text("This permanently deletes the history and statistics. It cannot be undone.")
            }
            .confirmationDialog("Also delete my snippets?", isPresented: $askDeleteSnippets, titleVisibility: .visible) {
                Button("Delete \(env.personalSnippets.count) snippet\(env.personalSnippets.count == 1 ? "" : "s")", role: .destructive) {
                    Task {
                        do { try await env.deleteAllPersonalSnippets() } catch {
                            AppEnvironment.log.error("Snippet delete failed: \(error.localizedDescription, privacy: .public)")
                        }
                        env.dataDidChange()
                    }
                }
                Button("Keep my snippets", role: .cancel) {}
            } message: {
                Text("Stats are reset. Your own snippets are separate; keep them or delete them too.")
            }
        }
    }

    private var aboutCard: some View {
        VStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(LinearGradient(colors: [Theme.indigo, Theme.violet, Theme.pink], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 64, height: 64)
                    .shadow(color: Theme.violet.opacity(0.4), radius: 10, y: 6)
                Image(systemName: "rectangle.stack.fill")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(.white)
            }
            Text("Memorise").font(.system(.title3, design: .rounded, weight: .bold))
            Text("Version \(Self.version)").font(.footnote.monospacedDigit()).foregroundStyle(.secondary)
            Text("github.com/…/Memorise").font(.caption).foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .accessibilityElement(children: .combine)
    }

    private static let version: String = {
        let info = Bundle.main.infoDictionary
        let v = info?["CFBundleShortVersionString"] as? String ?? "?"
        let b = info?["CFBundleVersion"] as? String ?? "?"
        return "\(v) (\(b))"
    }()

    private func prepareExport() async {
        exporting = true
        exportError = nil
        defer { exporting = false }
        do {
            var snapshot = try await env.store.exportSnapshot()
            // M4-8: user decks are included as data (backup only).
            snapshot.userDecks = env.userDeckFiles.isEmpty ? nil : env.userDeckFiles
            // M5 K4: the user's own snippets, only through their own export.
            snapshot.personalSnippets = env.personalSnippets.isEmpty ? nil : env.personalSnippets
            exportURLs = try await Task.detached(priority: .userInitiated) {
                let dir = FileManager.default.temporaryDirectory.appendingPathComponent("export", isDirectory: true)
                try? FileManager.default.removeItem(at: dir)
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                let stamp = ISO8601DateFormatter.string(from: snapshot.exportedAt, timeZone: .current, formatOptions: [.withFullDate])
                let json = dir.appendingPathComponent("memorise-\(stamp).json")
                let csv = dir.appendingPathComponent("memorise-attempts-\(stamp).csv")
                try Exporter.json(snapshot).write(to: json, options: .atomic)
                try Data(Exporter.csv(snapshot.attempts).utf8).write(to: csv, options: .atomic)
                return [json, csv]
            }.value
        } catch {
            exportError = "Export failed: \(error.localizedDescription)"
        }
    }

    private func reset(_ target: ResetTarget) async {
        do {
            switch target {
            case let .deck(id, _): try await env.store.reset(deck: id)
            case .all: try await env.store.resetAll()
            }
        } catch {
            AppEnvironment.log.error("Reset failed: \(error.localizedDescription, privacy: .public)")
        }
        resetTarget = nil
        env.dataDidChange()
        if case .all = target, !env.personalSnippets.isEmpty {
            // Let the first dialog finish dismissing before the second appears.
            try? await Task.sleep(for: .milliseconds(350))
            askDeleteSnippets = true
        }
    }
}

/// System-Settings-style row label with a gradient icon tile.
struct SettingLabel: View {
    let title: String
    let icon: String
    let colors: [Color]

    init(_ title: String, icon: String, colors: [Color]) {
        self.title = title
        self.icon = icon
        self.colors = colors
    }

    var body: some View {
        Label {
            Text(title)
        } icon: {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 29, height: 29)
                .background(
                    LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                )
        }
    }
}

#Preview {
    SettingsView().environment(AppEnvironment.preview())
}
