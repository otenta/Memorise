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
                    DeckChipCarousel(decks: env.catalog.decks, selected: deck?.id) { id in
                        withAnimation(Theme.spring) { selectedDeck = id }
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }

                if let deck {
                    Section {
                        StatsOverview(deck: deck, data: data)
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                    }
                    trendSection
                    if let section = env.deckUI(for: deck).statsSection(deck: deck, stats: data.stats) {
                        section
                    }
                    historySection
                }
            }
            .scrollContentBackground(.hidden)
            .auroraBackground(colors: deck?.subject.colors ?? Subject.music.colors, intensity: 0.6)
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
                HStack(spacing: 14) {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(deck?.subject.gradient ?? Subject.music.gradient)
                        .symbolEffect(.pulse, options: .repeating.speed(0.4))
                        .frame(width: 52, height: 52)
                        .background((deck?.subject.accent ?? Theme.indigo).opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(data.points.isEmpty ? "No trend yet" : "Almost there")
                            .font(.headline)
                        Text(data.points.isEmpty ? "Complete a session to see your trend." : "Complete one more session to see a trend.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 6)
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
        let accuracy = point?.baseline.accuracy
        return HStack(spacing: 12) {
            ZStack {
                if let accuracy {
                    RingGauge(value: accuracy, colors: accuracyColors(accuracy), lineWidth: 4)
                    Text(Fmt.percent(accuracy))
                        .font(.system(size: 10, weight: .heavy).monospacedDigit())
                        .minimumScaleFactor(0.6)
                } else {
                    Circle().fill(.primary.opacity(0.06))
                    Image(systemName: s.status == .abandoned ? "xmark" : "hourglass")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 40, height: 40)
            .accessibilityHidden(true)
            historyText(s, point: point)
        }
    }

    private func accuracyColors(_ a: Double) -> [Color] {
        a >= 0.85 ? [Theme.mint, Theme.teal] : a >= 0.6 ? [Theme.amber, .orange] : [Theme.rose, Theme.coral]
    }

    private func historyText(_ s: SessionRecord, point: SessionTrendPoint?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(s.startedAt, format: .dateTime.day().month().hour().minute())
                    .font(.subheadline.weight(.semibold))
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

// MARK: - Deck carousel

/// Horizontally scrolling deck chips; the selected one is filled with its subject gradient.
private struct DeckChipCarousel: View {
    let decks: [any Deck]
    let selected: DeckID?
    let select: (DeckID) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(decks, id: \.id) { deck in
                        chip(deck)
                            .id(deck.id)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
            }
            .scrollClipDisabled()
            .onAppear { if let selected { proxy.scrollTo(selected, anchor: .center) } }
            .onChange(of: selected) { _, id in
                guard let id else { return }
                withAnimation(Theme.softSpring) { proxy.scrollTo(id, anchor: .center) }
            }
        }
        .accessibilityIdentifier("statsDeckPicker")
    }

    private func chip(_ deck: any Deck) -> some View {
        let isOn = deck.id == selected
        return Button { select(deck.id) } label: {
            HStack(spacing: 6) {
                deck.subject.glyph
                    .font(.caption.weight(.bold))
                Text(deck.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(isOn ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
            .padding(.horizontal, 14).padding(.vertical, 9)
            .background {
                if isOn {
                    Capsule().fill(deck.subject.gradient)
                        .shadow(color: deck.subject.accent.opacity(0.4), radius: 8, y: 4)
                } else {
                    Capsule().fill(.regularMaterial)
                        .overlay(Capsule().strokeBorder(.primary.opacity(0.08), lineWidth: 1))
                }
            }
            .scaleEffect(isOn ? 1 : 0.96)
        }
        .buttonStyle(PressableStyle(scale: 0.92))
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

// MARK: - Overview

/// Three headline tiles: accuracy ring, median time, cards seen.
private struct StatsOverview: View {
    let deck: any Deck
    let data: DeckStatsData

    var body: some View {
        let info = DeckRowInfo.make(cardCount: data.stats.count, stats: data.stats.values)
        let seen = data.stats.values.filter { $0.attempts > 0 }.count
        let sessions = data.points.count
        HStack(spacing: 10) {
            tile(title: "Accuracy") {
                ZStack {
                    RingGauge(value: info.accuracy ?? 0, colors: [Theme.mint, Theme.teal], lineWidth: 6)
                    Text(info.accuracy.map { Fmt.percent($0) } ?? "–")
                        .font(.system(.caption, design: .rounded, weight: .heavy).monospacedDigit())
                        .contentTransition(.numericText())
                }
                .frame(width: 54, height: 54)
            }
            tile(title: "Median") {
                metric(info.medianMs.map { Fmt.seconds($0) } ?? "–", icon: "timer", colors: deck.subject.colors)
            }
            tile(title: sessions == 1 ? "Session" : "Sessions") {
                metric("\(sessions)", icon: "flame.fill", colors: [Theme.amber, Theme.coral])
            }
            tile(title: "Seen") {
                metric("\(seen)", icon: "eye.fill", colors: [Theme.violet, Theme.indigo])
            }
        }
        .padding(.horizontal, 16)
        .animation(Theme.softSpring, value: info)
        .accessibilityElement(children: .combine)
    }

    private func tile(title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(spacing: 6) {
            content()
                .frame(height: 54)
            Text(title.uppercased())
                .font(.system(size: 10, weight: .heavy, design: .rounded))
                .tracking(0.8)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(.white.opacity(0.35), lineWidth: 1))
        .shadow(color: deck.subject.accent.opacity(0.10), radius: 6, y: 3)
    }

    private func metric(_ value: String, icon: String, colors: [Color]) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing))
            Text(value)
                .font(.system(.title3, design: .rounded, weight: .bold).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .contentTransition(.numericText())
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
