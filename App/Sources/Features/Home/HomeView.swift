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
    /// Share of pool cards whose last answer was correct (R8-S2). `nil` while the deck is new, and always `nil`
    /// for decks that don't use coverage sessions (R9-UF2): those show an accuracy ring instead.
    var coverage: Double?
    var coveredCount: Int
    var accuracy: Double?
    var medianMs: Double?
    var lastSeen: Date?

    /// Every number comes from the same cards: `poolKeys` (the deck's pool for its current options).
    static func make(poolKeys: [ItemKey], stats: [ItemKey: ItemStats], usesCoverage: Bool) -> DeckRowInfo {
        var attempts = 0, correct = 0
        var times: [Double] = []
        var last: Date?
        for key in poolKeys {
            guard let s = stats[key], s.attempts > 0 else { continue }
            attempts += s.attempts
            correct += s.correctCount
            if let t = s.ewmaResponseMs { times.append(t) }
            if let seen = s.lastSeenAt, last.map({ seen > $0 }) ?? true { last = seen }
        }
        return DeckRowInfo(
            cardCount: poolKeys.count,
            coverage: usesCoverage ? DeckCoverage.fraction(poolKeys: poolKeys, stats: stats) : nil,
            coveredCount: DeckCoverage.coveredCount(poolKeys: poolKeys, stats: stats),
            accuracy: attempts > 0 ? Double(correct) / Double(attempts) : nil,
            medianMs: Statistics.median(times),
            lastSeen: last
        )
    }

    /// No pool card has been answered yet.
    var isNew: Bool { accuracy == nil }

    /// What the tile's ring shows: coverage on coverage decks, otherwise accuracy.
    var ringValue: Double? { coverage ?? accuracy }
    var ringCaption: String { coverage != nil ? "covered" : "accuracy" }

    var text: String {
        guard let accuracy else { return "\(cardCount) cards · New" }
        var parts = ["\(cardCount) cards"]
        if let coverage { parts.append("\(Fmt.percentFloor(coverage)) covered") }
        parts.append("\(Fmt.percent(accuracy)) accuracy")
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
    /// User deck open in the editor (M4-8).
    @State private var editingDeck: DeckID?
    @State private var newDeckPrompt = false
    @State private var newDeckTitle = ""
    /// Deck receiving screenshot words (M4-9).
    @State private var screenshotDeck: ScreenshotTarget?

    var body: some View {
        NavigationStack {
            ScrollView {
                // Eager on purpose (R7-F5): ~27 tiles lay out cheaply, and no cell recycling means
                // headers can never drift from their decks.
                VStack(alignment: .leading, spacing: 18) {
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
                    if let recent = recentDeck {
                        continueCard(recent).appearAnimation(index: 1)
                    }
                    // Stable, unique identity for every section and group (R7-F5): each subject is
                    // one container keyed by its raw value, each group by "subject.title", so a fast
                    // fling can never pair a recycled header with another section's tiles.
                    ForEach(Subject.allCases, id: \.rawValue) { subject in
                        subjectSection(subject)
                    }
                    myDecksSection.appearAnimation(index: Subject.allCases.count * 3 + 1)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
            // Held while the session cover is up: a fullScreenCover keeps Home alive, and its
            // TimelineView kept drawing at 30 Hz underneath (R6-7a, measured). Resumes on dismiss
            // from the same frame; also holds while the deck list scrolls.
            .auroraBackground(colors: [Theme.indigo, Theme.pink], running: launch == nil)
            .navigationTitle("Practice")
            .safeAreaInset(edge: .top, spacing: 0) {
                if env.persistenceWarning != nil { persistenceBanner }
            }
            .task(id: env.dataVersion) { await load() }
            #if DEBUG && targetEnvironment(simulator)
            // `-uiSetupDeck <id>` opens that deck's Setup sheet (UI screenshots).
            .task {
                if let id = UserDefaults.standard.string(forKey: "uiSetupDeck"), let deck = env.catalog.deck(id: DeckID(id)) {
                    setupDeck = DeckBox(deck: deck)
                }
                // `-uiSession <id>` starts a session straight away.
                if let id = UserDefaults.standard.string(forKey: "uiSession"), let deck = env.catalog.deck(id: DeckID(id)) {
                    launch = SessionLaunch(deck: deck, config: env.initialConfig(for: deck))
                }
                // `-uiImport YES` opens the AION screenshot import; `-uiEditAion YES` its deck editor.
                if UserDefaults.standard.bool(forKey: "uiImport") { await openAionImport() }
                if UserDefaults.standard.bool(forKey: "uiEditAion"), let id = try? await env.ensureAionDeck() {
                    editingDeck = id
                }
            }
            #endif
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
            .navigationDestination(item: $editingDeck) { UserDeckEditorView(deckID: $0) }
            .sheet(item: $screenshotDeck) { target in
                NavigationStack { ScreenshotImportView(deckID: target.id) }
            }
            .alert("New deck", isPresented: $newDeckPrompt) {
                TextField("Title", text: $newDeckTitle)
                    .accessibilityIdentifier("newDeckTitleField")
                Button("Cancel", role: .cancel) { newDeckTitle = "" }
                Button("Create") { Task { await createDeck() } }
                    .accessibilityIdentifier("newDeckCreateButton")
            } message: {
                Text("Add your own words; you can practise them like any Korean deck.")
            }
        }
    }

    /// One subject's header plus its display groups, as a single identity-stable container.
    @ViewBuilder
    private func subjectSection(_ subject: Subject) -> some View {
        let groups = deckGroups(for: subject)
        // User decks get their own "My decks" section below.
        if !groups.isEmpty {
            let sIndex = Subject.allCases.firstIndex(of: subject) ?? 0
            VStack(alignment: .leading, spacing: 18) {
                sectionHeader(subject).appearAnimation(index: sIndex * 3 + 2)
                ForEach(groups, id: \.id) { group in
                    VStack(alignment: .leading, spacing: 12) {
                        if !group.title.isEmpty {
                            groupHeader(group.title).appearAnimation(index: sIndex * 3 + 3 + group.index)
                        }
                        LazyVGrid(columns: gridColumns, spacing: 12) {
                            ForEach(Array(group.decks.enumerated()), id: \.element.id) { i, deck in
                                Button { setupDeck = DeckBox(deck: deck) } label: {
                                    DeckTile(deck: deck, info: info[deck.id], colors: subject.palette(group.index))
                                }
                                .buttonStyle(PressableStyle(scale: 0.95))
                                .accessibilityIdentifier("deck.\(deck.id.raw)")
                                .appearAnimation(index: sIndex * 3 + 3 + group.index + i / 2)
                            }
                        }
                    }
                    .id(group.id)
                }
            }
            .id(subject.rawValue)
        }
    }

    /// "My decks": user decks, each with Edit, plus "+ New deck" (PLAN_M4 M4-8).
    private var myDecksSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "person.crop.square.filled.and.at.rectangle")
                    .font(.footnote)
                    .foregroundStyle(.white)
                    .frame(width: 26, height: 26)
                    .background(Subject.korean.gradient, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                Text("My decks").font(.title3.weight(.bold))
            }
            .padding(.top, 6)
            .accessibilityAddTraits(.isHeader)
            ForEach(env.userDecks, id: \.id) { deck in
                VStack(alignment: .trailing, spacing: 6) {
                    Button {
                        if deck.entries.isEmpty { editingDeck = deck.id } else { setupDeck = DeckBox(deck: deck) }
                    } label: {
                        DeckCard(deck: deck, info: info[deck.id])
                    }
                    .buttonStyle(PressableStyle())
                    .accessibilityIdentifier("deck.\(deck.id.raw)")
                    .contextMenu {
                        Button { editingDeck = deck.id } label: { Label("Edit deck", systemImage: "pencil") }
                    }
                    Button { editingDeck = deck.id } label: {
                        Label(deck.entries.isEmpty ? "Add words" : "Edit", systemImage: "pencil")
                            .font(.footnote.weight(.semibold))
                    }
                    .buttonStyle(.borderless)
                    .accessibilityIdentifier("editDeck.\(deck.id.raw)")
                }
            }
            Button { newDeckPrompt = true } label: {
                Label("New deck", systemImage: "plus")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .glassCard(radius: 18, tint: Theme.pink)
            }
            .buttonStyle(PressableStyle())
            .accessibilityIdentifier("newDeckButton")
            Button { Task { await openAionImport() } } label: {
                Label("AION 2 words from a screenshot", systemImage: "text.viewfinder")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .glassCard(radius: 18, tint: Theme.indigo)
            }
            .buttonStyle(PressableStyle())
            .accessibilityIdentifier("aionScreenshotButton")
        }
    }

    private func openAionImport() async {
        do {
            screenshotDeck = ScreenshotTarget(id: try await env.ensureAionDeck())
        } catch {
            AppEnvironment.log.error("AION deck failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func createDeck() async {
        let title = newDeckTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        newDeckTitle = ""
        guard !title.isEmpty else { return }
        var rng = SplitMix64(seed: UInt64.random(in: .min ... .max))
        let id = UserDecks.newDeckID(existing: Set(env.catalog.decks.map(\.id.raw)), using: &rng)
        do {
            try await env.saveUserDeck(UserDecks.newDeck(id: id, title: title))
            editingDeck = DeckID(id)
        } catch {
            AppEnvironment.log.error("Create deck failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private var gridColumns: [GridItem] {
        [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
    }

    /// One display group of built-in decks; `id` is unique across subjects (R7-F5).
    private struct DeckGroup {
        let id: String
        let index: Int
        let title: String
        var decks: [any Deck]
    }

    /// Built-in decks of a subject, split into display groups (order kept, empty group names allowed).
    private func deckGroups(for subject: Subject) -> [DeckGroup] {
        var out: [DeckGroup] = []
        for deck in env.catalog.decks(for: subject) where !UserDecks.isUserDeckID(deck.id) {
            if let last = out.indices.last, out[last].title == deck.group {
                out[last].decks.append(deck)
            } else {
                // Index suffix keeps ids unique even if a group title recurs non-adjacently.
                let id = "\(subject.rawValue).\(deck.group).\(out.count)"
                out.append(DeckGroup(id: id, index: out.count, title: deck.group, decks: [deck]))
            }
        }
        return out
    }

    /// The most recently practised deck, if any.
    private var recentDeck: (any Deck)? {
        let best = info.compactMap { id, i in i.lastSeen.map { (id, $0) } }.max { $0.1 < $1.1 }
        return best.flatMap { env.catalog.deck(id: $0.0) }
    }

    private func continueCard(_ deck: any Deck) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Jump back in", systemImage: "arrow.clockwise.circle.fill")
                .font(.system(.caption, design: .rounded, weight: .heavy))
                .tracking(1.2)
                .textCase(.uppercase)
                .foregroundStyle(deck.subject.accent)
                .padding(.leading, 4)
            Button { setupDeck = DeckBox(deck: deck) } label: {
                DeckCard(deck: deck, info: info[deck.id])
            }
            .buttonStyle(PressableStyle())
            .accessibilityIdentifier("continueDeck")
        }
        .transition(.scale(scale: 0.95).combined(with: .opacity))
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

    private func groupHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.caption.weight(.heavy))
            .tracking(1.5)
            .foregroundStyle(.secondary)
            .padding(.top, 4)
            .padding(.leading, 4)
            .accessibilityAddTraits(.isHeader)
            .accessibilityIdentifier("deckGroup.\(title)")
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
        // One store round trip for every deck, and cached pool sizes (R5-2).
        let decks = env.catalog.decks
        let all = (try? await env.store.stats(forDecks: decks.map(\.id))) ?? [:]
        var result: [DeckID: DeckRowInfo] = [:]
        result.reserveCapacity(decks.count)
        for deck in decks {
            let keys = env.cardKeys(for: deck, options: env.initialConfig(for: deck).options)
            result[deck.id] = .make(poolKeys: keys, stats: all[deck.id] ?? [:], usesCoverage: deck.usesCoverageSessions)
        }
        withAnimation(Theme.softSpring) { info = result }
    }
}

/// White ring on a deck tile: coverage (a checkmark only when every pool card is covered) or, for decks
/// without coverage sessions, accuracy. Percentages round down, so 99.6 % never reads as 100 %.
private struct DeckRing: View {
    let info: DeckRowInfo
    let lineWidth: CGFloat
    let fontSize: CGFloat

    var body: some View {
        if let value = info.ringValue {
            let done = info.coverage != nil && info.cardCount > 0 && info.coveredCount == info.cardCount
            ZStack {
                RingGauge(value: value, colors: [.white, .white.opacity(0.7)], lineWidth: lineWidth)
                if done {
                    Image(systemName: "checkmark")
                        .font(.system(size: fontSize + 3, weight: .heavy))
                        .foregroundStyle(.white)
                } else {
                    Text(Fmt.percentFloor(value))
                        .font(.system(size: fontSize, weight: .heavy).monospacedDigit())
                        .foregroundStyle(.white)
                        .minimumScaleFactor(0.6)
                        .contentTransition(.numericText(value: value))
                }
            }
        }
    }
}

extension View {
    /// The tile is one accessibility element, so the ring's state is exposed here (R9-UF2 b).
    fileprivate func deckTileAccessibility(_ deck: any Deck, info: DeckRowInfo?) -> some View {
        accessibilityElement(children: .ignore)
            .accessibilityLabel("\(deck.title). \(deck.subtitle). \(info?.text ?? "")")
            .accessibilityValue(info?.ringValue.map { "\(Fmt.percentFloor($0)) \(info?.ringCaption ?? "")" } ?? "")
            .accessibilityAddTraits(.isButton)
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
                if let info, info.ringValue != nil {
                    VStack(spacing: 2) {
                        DeckRing(info: info, lineWidth: 5, fontSize: 12)
                            .frame(width: 50, height: 50)
                        Text(info.ringCaption)
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.8))
                    }
                }
            }
            HStack(spacing: 8) {
                if let info {
                    chip("rectangle.stack.fill", "\(info.cardCount)")
                    if info.isNew {
                        chip("sparkles", "New")
                    }
                    // Accuracy is already the ring on decks without coverage.
                    if info.coverage != nil, let a = info.accuracy { chip("checkmark.circle", Fmt.percent(a)) }
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
        .deckTileAccessibility(deck, info: info)
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

/// Compact gradient tile used in the Home grid.
private struct DeckTile: View {
    let deck: any Deck
    let info: DeckRowInfo?
    let colors: [Color]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                badge
                Spacer(minLength: 4)
                if let info, info.ringValue != nil {
                    DeckRing(info: info, lineWidth: 3.5, fontSize: 9)
                        .frame(width: 34, height: 34)
                }
            }
            Spacer(minLength: 10)
            Text(deck.title)
                .font(.system(.headline, design: .rounded, weight: .bold))
                .foregroundStyle(.white)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
                .multilineTextAlignment(.leading)
            Text(deck.subtitle)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .padding(.top, 2)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
        .background {
            let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
            shape.fill(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay(alignment: .topTrailing) {
                    deck.subject.glyph
                        .font(.system(size: 78))
                        .foregroundStyle(.white.opacity(0.13))
                        .rotationEffect(.degrees(-14))
                        .offset(x: 20, y: info?.ringValue == nil ? -6 : 34)
                }
                .overlay {
                    shape.fill(LinearGradient(colors: [.white.opacity(0.25), .clear], startPoint: .top, endPoint: .center))
                }
                .overlay { shape.strokeBorder(.white.opacity(0.18), lineWidth: 1) }
                .clipShape(shape)
                .shadow(color: colors[0].opacity(0.35), radius: 12, y: 7)
        }
        .deckTileAccessibility(deck, info: info)
    }

    /// Card count, or "New" for never-practised decks.
    @ViewBuilder private var badge: some View {
        if let info {
            HStack(spacing: 4) {
                Image(systemName: info.isNew ? "sparkles" : "rectangle.stack.fill")
                Text(info.isNew ? "New · \(info.cardCount)" : "\(info.cardCount)")
            }
            .font(.caption2.weight(.bold).monospacedDigit())
            .foregroundStyle(.white)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(.white.opacity(0.22), in: Capsule())
        } else {
            Text("00 cards")
                .font(.caption2.weight(.bold))
                .padding(.horizontal, 8).padding(.vertical, 4)
                .redacted(reason: .placeholder)
        }
    }
}

extension Subject {
    /// Per-group gradient pairs so display groups read as distinct families.
    func palette(_ index: Int) -> [Color] {
        let sets: [[Color]] = switch self {
        case .music: [[Theme.indigo, Theme.violet], [Theme.violet, Theme.pink], [Theme.teal, Theme.indigo], [Theme.indigo, Theme.teal]]
        case .korean: [[Theme.coral, Theme.pink], [Theme.pink, Theme.violet], [Theme.amber, Theme.coral], [Theme.rose, Theme.pink]]
        }
        return sets[index % sets.count]
    }
}

/// Deck receiving screenshot words.
private struct ScreenshotTarget: Identifiable {
    let id: DeckID
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

#Preview("Ring states") {
    let states: [DeckRowInfo] = [
        DeckRowInfo(cardCount: 664, coverage: 0.2, coveredCount: 133, accuracy: 0.8),
        DeckRowInfo(cardCount: 664, coverage: 659.0 / 664, coveredCount: 659, accuracy: 0.9),
        DeckRowInfo(cardCount: 664, coverage: 1.0, coveredCount: 664, accuracy: 0.95),
        DeckRowInfo(cardCount: 40, coverage: nil, coveredCount: 0, accuracy: 0.74),
    ]
    HStack(spacing: 12) {
        ForEach(states.indices, id: \.self) { i in
            ZStack {
                LinearGradient(colors: [Theme.coral, Theme.pink], startPoint: .topLeading, endPoint: .bottomTrailing)
                VStack(spacing: 2) {
                    DeckRing(info: states[i], lineWidth: 5, fontSize: 12).frame(width: 50, height: 50)
                    Text(states[i].ringCaption).font(.caption2).foregroundStyle(.white.opacity(0.8))
                }
            }
            .frame(width: 80, height: 100)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }
    .padding()
}
