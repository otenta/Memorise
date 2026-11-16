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
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    greeting.appearAnimation()
                    // Validation problems first: they can silently mix stats, so they're the more dangerous.
                    if !env.deckReport.validationWarnings.isEmpty && !validationDismissed {
                        issueRow(
                            "Deck data has problems — stats for affected words may be mixed",
                            color: .red, details: env.deckReport.validationWarnings, id: "deckValidationRow"
                        ) { withAnimation(Theme.spring) { validationDismissed = true } }
                        .transition(.scale(scale: 0.9).combined(with: .opacity))
                    }
                    if !env.deckReport.loadFailures.isEmpty && !loadFailuresDismissed {
                        issueRow(
                            "Some decks couldn't be loaded",
                            color: .orange, details: env.deckReport.loadFailures, id: "deckLoadFailuresRow"
                        ) { withAnimation(Theme.spring) { loadFailuresDismissed = true } }
                        .transition(.scale(scale: 0.9).combined(with: .opacity))
                    }
                    ForEach(Array(Subject.allCases.enumerated()), id: \.element) { sIndex, subject in
                        let decks = env.catalog.decks(for: subject)
                        if !decks.isEmpty {
                            sectionHeader(subject).appearAnimation(index: sIndex * 3 + 1)
                            ForEach(Array(decks.enumerated()), id: \.element.id) { i, deck in
                                Button { setupDeck = DeckBox(deck: deck) } label: {
                                    DeckCard(deck: deck, info: info[deck.id])
                                }
                                .buttonStyle(PressableStyle())
                                .accessibilityIdentifier("deck.\(deck.id.raw)")
                                .appearAnimation(index: sIndex * 3 + 2 + i)
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
            .background { AuroraBackground(colors: [Theme.indigo, Theme.pink]) }
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

    private var greeting: some View {
        let hour = Calendar.current.component(.hour, from: .now)
        let text = switch hour {
        case 5..<12: "Good morning"
        case 12..<18: "Good afternoon"
        default: "Good evening"
        }
        return Text("\(text) — what are we drilling today?")
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.secondary)
            .padding(.top, 2)
    }

    private func sectionHeader(_ subject: Subject) -> some View {
        HStack(spacing: 8) {
            subject.glyph
                .font(.footnote)
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(subject.gradient, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            Text(subject.title).font(.title3.weight(.bold))
        }
        .padding(.top, 6)
        .accessibilityAddTraits(.isHeader)
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
        .background(Theme.wrongGradient)
        .accessibilityIdentifier("persistenceWarningBanner")
    }

    private func issueRow(_ title: String, color: Color, details: [String], id: String, dismiss: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                Label(title, systemImage: "exclamationmark.triangle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(color)
                Spacer()
                Button(action: dismiss) {
                    Image(systemName: "xmark.circle.fill").font(.title3).foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Dismiss")
            }
            DisclosureGroup("Details") {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(details, id: \.self) { Text($0).font(.caption).foregroundStyle(.secondary) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 4)
            }
            .font(.subheadline)
            .tint(color)
        }
        .padding(16)
        .glassCard(radius: 20, tint: color)
        .accessibilityIdentifier(id)
    }

    private func load() async {
        var result: [DeckID: DeckRowInfo] = [:]
        for deck in env.catalog.decks {
            let count = deck.cards(options: env.initialConfig(for: deck).options).count
            let stats = (try? await env.store.stats(for: deck.id)) ?? [:]
            result[deck.id] = .make(cardCount: count, stats: stats.values)
        }
        withAnimation(Theme.softSpring) { info = result }
    }
}

/// Gradient hero card for one deck.
private struct DeckCard: View {
    let deck: any Deck
    let info: DeckRowInfo?

    var body: some View {
        let subject = deck.subject
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(deck.title)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.white)
                    Text(deck.subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.85))
                        .lineLimit(2)
                }
                Spacer(minLength: 12)
                if let accuracy = info?.accuracy {
                    ZStack {
                        RingGauge(value: accuracy, colors: [.white, .white.opacity(0.7)], lineWidth: 5)
                        Text(Fmt.percent(accuracy))
                            .font(.caption2.weight(.heavy).monospacedDigit())
                            .foregroundStyle(.white)
                    }
                    .frame(width: 50, height: 50)
                }
            }
            HStack(spacing: 8) {
                if let info {
                    chip("rectangle.stack.fill", "\(info.cardCount)")
                    if info.accuracy == nil {
                        chip("sparkles", "New")
                    }
                    if let m = info.medianMs { chip("timer", Fmt.seconds(m)) }
                    if let last = info.lastSeen { chip("clock.arrow.circlepath", Fmt.relative(last)) }
                } else {
                    chip("rectangle.stack.fill", "…").redacted(reason: .placeholder)
                }
                Spacer(minLength: 0)
                Image(systemName: "play.fill")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(subject.accent)
                    .frame(width: 36, height: 36)
                    .background(.white, in: Circle())
                    .shadow(color: .black.opacity(0.15), radius: 6, y: 3)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            let shape = RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
            shape.fill(subject.gradient)
                .overlay(alignment: .bottomTrailing) {
                    subject.glyph
                        .font(.system(size: 120))
                        .foregroundStyle(.white.opacity(0.12))
                        .rotationEffect(.degrees(-12))
                        .offset(x: 24, y: 30)
                }
                .overlay {
                    shape.fill(LinearGradient(colors: [.white.opacity(0.22), .clear], startPoint: .top, endPoint: .center))
                }
                .clipShape(shape)
                .shadow(color: subject.accent.opacity(0.4), radius: 16, y: 10)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(deck.title). \(deck.subtitle). \(info?.text ?? "")")
        .accessibilityAddTraits(.isButton)
    }

    private func chip(_ icon: String, _ text: String) -> some View {
        Label(text, systemImage: icon)
            .font(.caption.weight(.semibold).monospacedDigit())
            .labelStyle(.titleAndIcon)
            .foregroundStyle(.white)
            .lineLimit(1)
            .padding(.horizontal, 9).padding(.vertical, 5)
            .background(.white.opacity(0.2), in: Capsule())
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
