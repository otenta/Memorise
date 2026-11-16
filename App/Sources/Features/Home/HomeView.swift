import MemoriseCore
import SwiftUI

/// Identifies a session to launch.
struct SessionLaunch: Identifiable {
    let id = UUID()
    let deck: any Deck
    let config: SessionConfig
}

/// Per-deck stats line.
struct DeckRowInfo: Equatable {
    var cardCount: Int
    var accuracy: Double?
    var medianMs: Double?
    var lastSeen: Date?

    static func make(cardCount: Int, stats: some Collection<ItemStats>) -> DeckRowInfo {
        var attempts = 0, correct = 0
        var times: [Double] = []
        var last: Date?
        for s in stats where s.attempts > 0 {
            attempts += s.attempts
            correct += s.correctCount
            if let t = s.ewmaResponseMs { times.append(t) }
            if let seen = s.lastSeenAt, last.map({ seen > $0 }) ?? true { last = seen }
        }
        return DeckRowInfo(
            cardCount: cardCount,
            accuracy: attempts > 0 ? Double(correct) / Double(attempts) : nil,
            medianMs: Statistics.median(times),
            lastSeen: last
        )
    }

    var text: String {
        guard let accuracy else { return "\(cardCount) cards · New" }
        var parts = ["\(cardCount) cards", Fmt.percent(accuracy)]
        if let medianMs { parts.append("median \(Fmt.seconds(medianMs))") }
        if let lastSeen { parts.append("last: \(Fmt.relative(lastSeen))") }
        return parts.joined(separator: " · ")
    }
}

struct HomeView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var info: [DeckID: DeckRowInfo] = [:]
    @State private var setupDeck: DeckBox?
    @State private var launch: SessionLaunch?
    @State private var pendingLaunch: SessionLaunch?
    @State private var validationDismissed = false
    @State private var loadFailuresDismissed = false

    var body: some View {
        NavigationStack {
            List {
                // Validation problems first: they can silently mix stats, so they're the more dangerous.
                if !env.deckReport.validationWarnings.isEmpty && !validationDismissed {
                    Section {
                        issueRow(
                            "Deck data has problems — stats for affected words may be mixed",
                            color: .red, details: env.deckReport.validationWarnings, id: "deckValidationRow"
                        ) { validationDismissed = true }
                    }
                }
                if !env.deckReport.loadFailures.isEmpty && !loadFailuresDismissed {
                    Section {
                        issueRow(
                            "Some decks couldn't be loaded",
                            color: .orange, details: env.deckReport.loadFailures, id: "deckLoadFailuresRow"
                        ) { loadFailuresDismissed = true }
                    }
                }
                ForEach(Subject.allCases, id: \.self) { subject in
                    let decks = env.catalog.decks(for: subject)
                    if !decks.isEmpty {
                        Section(subject.title) {
                            ForEach(decks, id: \.id) { deck in
                                Button { setupDeck = DeckBox(deck: deck) } label: { row(deck) }
                                    .buttonStyle(.plain)
                                    .accessibilityIdentifier("deck.\(deck.id.raw)")
                            }
                        }
                    }
                }
            }
            .navigationTitle("Practice")
            .safeAreaInset(edge: .top, spacing: 0) {
                if env.persistenceWarning != nil { persistenceBanner }
            }
            .task(id: env.dataVersion) { await load() }
            .sheet(item: $setupDeck, onDismiss: {
                // Present the session only once the sheet is fully gone.
                launch = pendingLaunch
                pendingLaunch = nil
            }) { box in
                SessionSetupView(deck: box.deck) { config in
                    pendingLaunch = SessionLaunch(deck: box.deck, config: config)
                    setupDeck = nil
                }
            }
            .fullScreenCover(item: $launch) { l in
                SessionView(deck: l.deck, config: l.config)
            }
        }
    }

    private var persistenceBanner: some View {
        Label(
            "Progress isn't being saved this session. Restart the app; if this persists, export your data from Settings.",
            systemImage: "exclamationmark.triangle.fill"
        )
        .font(.footnote.weight(.semibold))
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.red)
        .accessibilityIdentifier("persistenceWarningBanner")
    }

    private func issueRow(_ title: String, color: Color, details: [String], id: String, dismiss: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top) {
                Label(title, systemImage: "exclamationmark.triangle").foregroundStyle(color)
                Spacer()
                Button(action: dismiss) {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Dismiss")
            }
            DisclosureGroup("Details") {
                ForEach(details, id: \.self) { Text($0).font(.caption).foregroundStyle(.secondary) }
            }
            .font(.subheadline)
        }
        .accessibilityIdentifier(id)
    }

    private func row(_ deck: any Deck) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(deck.title).font(.headline).foregroundStyle(.primary)
            Text(deck.subtitle).font(.subheadline).foregroundStyle(.secondary)
            if let i = info[deck.id] {
                Text(i.text).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    private func load() async {
        var result: [DeckID: DeckRowInfo] = [:]
        for deck in env.catalog.decks {
            let count = deck.cards(options: env.initialConfig(for: deck).options).count
            let stats = (try? await env.store.stats(for: deck.id)) ?? [:]
            result[deck.id] = .make(cardCount: count, stats: stats.values)
        }
        info = result
    }
}

/// `Identifiable` wrapper so an existential deck can drive `.sheet(item:)`.
struct DeckBox: Identifiable {
    let deck: any Deck
    var id: DeckID { deck.id }
}

extension Subject {
    var title: String {
        switch self {
        case .music: "Music"
        case .korean: "Korean"
        }
    }
}

#Preview {
    HomeView().environment(AppEnvironment.preview())
}
