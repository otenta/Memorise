import MemoriseCore
import SwiftUI

/// Settings tab (§11.7).
struct SettingsView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var exportURLs: [URL] = []
    @State private var exporting = false
    @State private var exportError: String?
    @State private var resetTarget: ResetTarget?
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
                    Picker("Note names", selection: $s.noteNaming) {
                        Text("Letter (A)").tag(NoteNaming.letter)
                        Text("Solfège (La)").tag(NoteNaming.solfege)
                        Text("Both (A (La))").tag(NoteNaming.both)
                    }
                    Picker("Seventh degree", selection: $s.solfegeVariant) {
                        Text("Si").tag(SolfegeVariant.si)
                        Text("Ti").tag(SolfegeVariant.ti)
                    }
                    Toggle("Left-handed", isOn: $s.leftHanded)
                    Picker("String order", selection: $s.highEOnTop) {
                        Text("High E on top (tab)").tag(true)
                        Text("Low E on top").tag(false)
                    }
                    Picker("Max fret for new setups", selection: $s.defaultMaxFret) {
                        ForEach(FretboardOptions.maxFretPresets, id: \.self) { Text("\($0)").tag($0) }
                    }
                    Toggle("Show string hint (low E…)", isOn: $s.showStringHint)
                } header: {
                    Text("Music")
                } footer: {
                    Text("Decks you've already practised keep their last settings.")
                }

                Section("Korean") {
                    Toggle("Auto-play pronunciation", isOn: $s.autoPlayPronunciation)
                    VStack(alignment: .leading) {
                        Text("Speech rate")
                        Slider(value: $s.speechRate, in: 0.2...0.6) {
                            Text("Speech rate")
                        } minimumValueLabel: {
                            Image(systemName: "tortoise")
                        } maximumValueLabel: {
                            Image(systemName: "hare")
                        }
                    }
                    Button("Test voice") { env.speech.speak("안녕하세요", rate: s.speechRate) }
                    Toggle("Show romanization on reveal", isOn: $s.showRomanization)
                    if !env.speech.hasKoreanVoice {
                        Text("No Korean voice installed. Add one in Settings → Accessibility → Spoken Content → Voices → Korean.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }

                Section("Session") {
                    Toggle("Tap anywhere for OK", isOn: $s.tapAnywhereForOK)
                    Toggle("Show timer during prompt", isOn: $s.showTimer)
                    Toggle("Haptics", isOn: $s.hapticsEnabled)
                }

                Section {
                    if exportURLs.isEmpty {
                        Button {
                            Task { await prepareExport() }
                        } label: {
                            HStack {
                                Text("Export data")
                                if exporting { Spacer(); ProgressView() }
                            }
                        }
                        .disabled(exporting)
                        .accessibilityIdentifier("exportButton")
                    } else {
                        ShareLink(items: exportURLs) {
                            Label("Share export (JSON + CSV)", systemImage: "square.and.arrow.up")
                        }
                    }
                    if let exportError {
                        Text(exportError).font(.footnote).foregroundStyle(.red)
                    }
                    Menu("Reset stats…") {
                        ForEach(env.catalog.decks, id: \.id) { deck in
                            Button(deck.title, role: .destructive) { resetTarget = .deck(deck.id, deck.title) }
                        }
                        Divider()
                        Button("All decks", role: .destructive) { resetTarget = .all }
                    }
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("resetMenu")
                } header: {
                    Text("Data")
                } footer: {
                    Text("Export includes every session, attempt and item statistic.")
                }

                #if DEBUG && targetEnvironment(simulator)
                Section("Developer") {
                    Button(seeding ? "Seeding…" : "Seed 1 year of synthetic history") {
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
                    }
                    .disabled(seeding)
                }
                #endif

                Section("About") {
                    LabeledContent("Version", value: Self.version)
                    LabeledContent("Source", value: "github.com/…/Memorise")
                }
            }
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
        }
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
            let snapshot = try await env.store.exportSnapshot()
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
    }
}

#Preview {
    SettingsView().environment(AppEnvironment.preview())
}
