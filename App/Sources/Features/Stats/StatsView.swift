import Charts
import MemoriseCore
import SwiftUI

/// Loaded statistics of one deck (no raw attempts are kept on the main actor).
struct DeckStatsData {
    var sessions: [SessionRecord] = []
    var stats: [ItemKey: ItemStats] = [:]
    var points: [SessionTrendPoint] = []
    var pointsByID: [UUID: SessionTrendPoint] = [:]

    static func load(deck: DeckID, store: any StatsStore) async throws -> DeckStatsData {
        async let sessions = store.sessions(for: deck)
        async let stats = store.stats(for: deck)
        async let points = store.trendPoints(for: deck)
        var data = DeckStatsData()
        data.sessions = try await sessions
        data.stats = try await stats
        data.points = try await points
        data.pointsByID = Dictionary(uniqueKeysWithValues: data.points.map { ($0.id, $0) })
        return data
    }

    /// Baseline of the last completed session before `session`.
    func previousBaseline(before session: SessionRecord) -> SessionBaseline? {
        points.last { $0.session.startedAt < session.startedAt }?.baseline
    }
}

struct StatsView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var selectedDeck: DeckID?
    @State private var data = DeckStatsData()
    @State private var showAccuracy = false
    @State private var isVisible = false
    @State private var loadedKey: LoadKey?

    private var deck: (any Deck)? {
        selectedDeck.flatMap(env.catalog.deck(id:)) ?? env.catalog.decks.first
    }

    private struct LoadKey: Equatable {
        let deck: DeckID?
        let version: Int
    }

    private struct TaskKey: Equatable {
        let load: LoadKey
        let visible: Bool
    }

    var body: some View {
        let key = LoadKey(deck: deck?.id, version: env.dataVersion)
        NavigationStack {
            List {
                Section {
                    Picker("Deck", selection: Binding(
                        get: { deck?.id },
                        set: { selectedDeck = $0 }
                    )) {
                        ForEach(env.catalog.decks, id: \.id) { Text($0.title).tag(Optional($0.id)) }
                    }
                    .accessibilityIdentifier("statsDeckPicker")
                }

                if let deck {
                    trendSection
                    if let section = env.deckUI(for: deck).statsSection(deck: deck, stats: data.stats) {
                        section
                    }
                    historySection
                }
            }
            .scrollContentBackground(.hidden)
            .background { AuroraBackground(colors: deck?.subject.colors ?? Subject.music.colors, intensity: 0.6) }
            .animation(Theme.softSpring, value: deck?.id)
            .navigationTitle("Stats")
            .navigationDestination(for: SessionRecord.self) { s in
                SessionHistoryDetail(session: s, deck: deck, previous: data.previousBaseline(before: s))
            }
        }
        .onAppear { isVisible = true }
        .onDisappear { isVisible = false }
        .task(id: TaskKey(load: key, visible: isVisible)) { await load(key) }
    }

    /// Loads only while visible and when the deck or stored data changed since the last load.
    private func load(_ key: LoadKey) async {
        guard isVisible, loadedKey != key, let id = key.deck else { return }
        do {
            let clock = ContinuousClock()
            let start = clock.now
            let loaded = try await DeckStatsData.load(deck: id, store: env.store)
            let ms = (clock.now - start).timeInterval * 1_000
            AppEnvironment.log.info("Stats load \(id.raw, privacy: .public): \(ms, format: .fixed(precision: 1)) ms, \(loaded.sessions.count) sessions")
            guard !Task.isCancelled else { return }
            data = loaded
            loadedKey = key
        } catch {
            AppEnvironment.log.error("Stats load failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: Trend

    @ViewBuilder private var trendSection: some View {
        Section {
            if data.points.count < 2 {
                Text(data.points.isEmpty ? "Complete a session to see your trend." : "Complete one more session to see a trend.")
                    .foregroundStyle(.secondary)
            } else {
                Picker("Metric", selection: $showAccuracy) {
                    Text("Median time").tag(false)
                    Text("Accuracy").tag(true)
                }
                .pickerStyle(.segmented)
                Chart(data.points) { p in
                    if showAccuracy {
                        if let a = p.baseline.accuracy {
                            trendMarks(date: p.session.startedAt, label: "Accuracy", value: a * 100)
                        }
                    } else if let m = p.baseline.medianMs {
                        trendMarks(date: p.session.startedAt, label: "Seconds", value: m / 1_000)
                    }
                }
                .animation(Theme.softSpring, value: showAccuracy)
                .chartYAxisLabel(showAccuracy ? "%" : "s")
                .chartYScale(domain: .automatic(includesZero: true))
                .frame(height: 180)
                .padding(.vertical, 6)
            }
        } header: {
            Text("Trend")
        }
    }

    @ChartContentBuilder
    private func trendMarks(date: Date, label: String, value: Double) -> some ChartContent {
        let colors = showAccuracy ? [Theme.mint, Theme.teal] : (deck?.subject.colors ?? Subject.music.colors)
        AreaMark(x: .value("Date", date), y: .value(label, value))
            .interpolationMethod(.catmullRom)
            .foregroundStyle(LinearGradient(colors: [colors[0].opacity(0.35), colors[0].opacity(0.02)], startPoint: .top, endPoint: .bottom))
        LineMark(x: .value("Date", date), y: .value(label, value))
            .interpolationMethod(.catmullRom)
            .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round))
            .foregroundStyle(LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing))
        PointMark(x: .value("Date", date), y: .value(label, value))
            .symbolSize(50)
            .foregroundStyle(colors[1])
    }

    // MARK: History

    @ViewBuilder private var historySection: some View {
        Section("History") {
            if data.sessions.isEmpty {
                Text("No sessions yet.").foregroundStyle(.secondary)
            }
            ForEach(data.sessions.reversed()) { s in
                NavigationLink(value: s) { historyRow(s) }
            }
        }
    }

    private func historyRow(_ s: SessionRecord) -> some View {
        let point = data.pointsByID[s.id]
        return VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(s.startedAt, format: .dateTime.day().month().hour().minute())
                if s.config.inputMode != .touch {
                    Image(systemName: s.config.inputMode.systemImage).font(.caption).foregroundStyle(.secondary)
                        .accessibilityLabel(s.config.inputMode.title)
                }
                if let t = s.config.options.tuning, t != .standard {
                    Text(Tuning.preset(t).name).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 8) {
                if let point {
                    Text("\(point.graded) cards")
                    Text(Fmt.percent(point.baseline.accuracy))
                    Text("median \(Fmt.seconds(point.baseline.medianMs))")
                } else {
                    Text(s.status == .abandoned ? "Abandoned" : "In progress")
                }
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
        }
    }
}

/// Loads one session's attempts on demand and shows its summary.
private struct SessionHistoryDetail: View {
    let session: SessionRecord
    let deck: (any Deck)?
    let previous: SessionBaseline?

    @Environment(AppEnvironment.self) private var env
    @State private var summary: SessionSummary?
    @State private var loadError: String?
    @State private var attempt = 0

    private struct LoadID: Equatable {
        let session: UUID
        let attempt: Int
    }

    var body: some View {
        Group {
            if let summary {
                SummaryView(summary: summary, deck: deck)
            } else if let loadError {
                ContentUnavailableView {
                    Label("Couldn't load this session", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(loadError)
                } actions: {
                    Button("Retry") { attempt += 1 }
                        .accessibilityIdentifier("historyRetryButton")
                }
            } else {
                ProgressView()
            }
        }
        .task(id: LoadID(session: session.id, attempt: attempt)) {
            loadError = nil
            do {
                let attempts = try await env.store.attempts(for: session.id)
                summary = SessionSummary.build(session: session, attempts: attempts, previous: previous)
            } catch {
                AppEnvironment.log.error("History load \(session.id.uuidString, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
                loadError = error.localizedDescription
            }
        }
    }
}

#Preview {
    StatsView().environment(AppEnvironment.preview())
}
