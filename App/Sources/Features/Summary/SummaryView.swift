import Charts
import MemoriseCore
import SwiftUI

/// Session summary (§11.4). Used at session end and from Stats history.
struct SummaryView: View {
    let summary: SessionSummary
    let deck: (any Deck)?
    /// Answers that couldn't be persisted (live sessions only).
    var saveFailures = 0

    @Environment(AppEnvironment.self) private var env
    @State private var showAll = false
    @State private var labels: [ItemKey: String] = [:]
    @State private var appeared = false

    var body: some View {
        List {
            if saveFailures > 0 {
                Section {
                    Label("\(saveFailures) answer\(saveFailures == 1 ? "" : "s") couldn't be saved", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .accessibilityIdentifier("saveFailuresRow")
                }
            }
            if !summary.config.recoveredFields.isEmpty {
                Section {
                    Text("Some settings of this session couldn't be read; defaults are shown.")
                        .font(.caption).foregroundStyle(.secondary)
                        .accessibilityIdentifier("recoveredSettingsCaption")
                }
            }
            Section {
                VStack(spacing: 14) {
                    hero
                    tiles
                }
            }
            .listRowInsets(EdgeInsets(top: 8, leading: 4, bottom: 8, trailing: 4))
            .listRowBackground(Color.clear)

            if !chartRows.isEmpty {
                Section("Response times") { chart }
            }
            if !summary.slowest5.isEmpty {
                Section {
                    ForEach(summary.slowest5) { row($0) }
                } header: {
                    Text("Slowest")
                } footer: {
                    Text("These will show up more often.")
                }
            }
            if !summary.wrong.isEmpty {
                Section {
                    ForEach(summary.wrong) { row($0) }
                } header: {
                    Text("Missed")
                } footer: {
                    Text("These will show up more often.")
                }
            }
            if !summary.rows.isEmpty {
                Section {
                    DisclosureGroup("All cards (\(summary.rows.count))", isExpanded: $showAll) {
                        ForEach(summary.rows) { row($0, showHistory: true) }
                    }
                }
            }
            if summary.rows.isEmpty {
                ContentUnavailableView("No cards answered", systemImage: "rectangle.stack")
            }
        }
        .scrollContentBackground(.hidden)
        .background { AuroraBackground(colors: colors, intensity: 0.7) }
        .navigationTitle(summary.status == .abandoned ? "Session ended" : "Summary")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: summary.sessionID) { buildLabels() }
        .accessibilityIdentifier("summaryView")
    }

    private var colors: [Color] { deck?.subject.colors ?? Subject.music.colors }

    // MARK: Hero

    private var hero: some View {
        let accuracy = summary.accuracy ?? 0
        let (headline, symbol): (String, String) = switch accuracy {
        case 0.95...: ("Flawless!", "crown.fill")
        case 0.8..<0.95: ("Great run!", "flame.fill")
        case 0.6..<0.8: ("Solid practice", "hand.thumbsup.fill")
        default: ("Keep at it", "figure.strengthtraining.traditional")
        }
        return HStack(spacing: 20) {
            ZStack {
                RingGauge(value: accuracy, colors: [Theme.mint, Theme.teal, Theme.indigo], lineWidth: 12)
                VStack(spacing: 0) {
                    Text(Fmt.percent(summary.accuracy))
                        .font(.system(.title2, design: .rounded, weight: .heavy).monospacedDigit())
                    Text("accuracy").font(.caption2).foregroundStyle(.secondary)
                }
            }
            .frame(width: 104, height: 104)
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: symbol)
                    .font(.title2)
                    .foregroundStyle(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing))
                    .symbolEffect(.bounce, value: appeared)
                Text(summary.rows.isEmpty ? "Nothing yet" : headline)
                    .font(.system(.title2, design: .rounded, weight: .bold))
                Text(deck?.title ?? "Session")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(18)
        .glassCard(tint: colors[0])
        .onAppear { appeared = true }
        .accessibilityElement(children: .combine)
    }

    // MARK: Tiles

    private var tiles: some View {
        Grid(horizontalSpacing: 10, verticalSpacing: 10) {
            GridRow {
                StatTile(title: "Cards", value: "\(summary.gradedCount)", systemImage: "rectangle.stack.fill", tint: colors[0])
                StatTile(
                    title: "Accuracy", value: Fmt.percent(summary.accuracy),
                    delta: Fmt.delta(percentPoints: summary.accuracyDelta),
                    deltaColor: Palette.deltaColor(summary.accuracyDelta, lowerIsBetter: false, zero: Fmt.isZeroDelta(percentPoints:)),
                    systemImage: "target", tint: Theme.mint
                )
            }
            GridRow {
                StatTile(
                    title: "Median time", value: Fmt.seconds(summary.medianMs),
                    delta: Fmt.delta(ms: summary.medianDeltaMs),
                    deltaColor: Palette.deltaColor(summary.medianDeltaMs, lowerIsBetter: true, zero: Fmt.isZeroDelta(ms:)),
                    systemImage: "timer", tint: Theme.amber
                )
                StatTile(title: "Total time", value: Fmt.clock(summary.totalDuration), systemImage: "hourglass", tint: colors[1])
            }
        }
    }

    // MARK: Chart

    private var chartRows: [SessionSummary.Row] { summary.rows }

    private var chart: some View {
        Chart {
            ForEach(Array(chartRows.enumerated()), id: \.element.id) { i, r in
                BarMark(x: .value("Card", i + 1), y: .value("Seconds", Double(r.responseMs) / 1_000))
                    .foregroundStyle(by: .value("Result", r.correct ? "Correct" : "Wrong"))
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    .opacity(r.isRetry ? 0.5 : 1)
            }
            if let median = summary.medianMs {
                RuleMark(y: .value("Median", median / 1_000))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .foregroundStyle(.secondary)
                    .annotation(position: .top, alignment: .leading) {
                        Text("median \(Fmt.seconds(median))").font(.caption2).foregroundStyle(.secondary)
                    }
            }
        }
        .chartForegroundStyleScale(["Correct": Theme.correctGradient, "Wrong": Theme.wrongGradient])
        .chartYAxisLabel("s")
        .frame(height: 200)
        .padding(.vertical, 8)
    }

    // MARK: Rows

    private func row(_ r: SessionSummary.Row, showHistory: Bool = false) -> some View {
        HStack(spacing: 10) {
            Image(systemName: r.correct ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.title3)
                .foregroundStyle(r.correct ? Theme.correctGradient : Theme.wrongGradient)
            VStack(alignment: .leading, spacing: 2) {
                Text(labels[r.itemKey] ?? r.itemKey.raw).lineLimit(2)
                if r.isRetry {
                    Text("Retry").font(.caption2).foregroundStyle(.orange)
                }
            }
            Spacer()
            if showHistory, let ratio = r.ratioToHistory {
                Text(ratio > 1 ? "▲" : "▼")
                    .foregroundStyle(ratio > 1 ? Palette.wrong : Palette.correct)
                    .accessibilityLabel(ratio > 1 ? "slower than usual" : "faster than usual")
            }
            Text(Fmt.seconds(r.responseMs)).font(.body.monospacedDigit())
        }
        .accessibilityElement(children: .combine)
    }

    private func buildLabels() {
        var lookup: [ItemKey: Card] = [:]
        if summary.rows.contains(where: { $0.card == nil }), let deck {
            for c in deck.cards(options: summary.config.options) { lookup[c.key] = c }
        }
        var result: [ItemKey: String] = [:]
        for r in summary.rows where result[r.itemKey] == nil {
            result[r.itemKey] = CardLabel.text(r.card ?? lookup[r.itemKey], key: r.itemKey, settings: env.settings)
        }
        labels = result
    }
}

#Preview {
    let deck = FretboardNotesDeck()
    let cards = deck.cards(options: deck.defaultOptions)
    let session = SessionRecord(
        id: UUID(), deckID: deck.id, startedAt: .now.addingTimeInterval(-120), endedAt: .now,
        status: .completed, config: .default(for: deck)
    )
    let attempts = cards.prefix(12).enumerated().map { i, c in
        Attempt(id: UUID(), sessionID: session.id, itemKey: c.key, deckID: deck.id, index: i, shownAt: .now,
                responseMs: 800 + (i * 397) % 3_000, gradeMs: 300, correct: i % 4 != 0, isRetry: false, wasInterrupted: false)
    }
    let summary = SessionSummary.build(
        session: session, attempts: attempts, cardLookup: { k in cards.first { $0.key == k } },
        previous: SessionBaseline(medianMs: 2_100, accuracy: 0.7)
    )
    return NavigationStack { SummaryView(summary: summary, deck: deck) }
        .environment(AppEnvironment.preview())
}
