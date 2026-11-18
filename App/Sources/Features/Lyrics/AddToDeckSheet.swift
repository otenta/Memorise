import MemoriseCore
import SwiftUI

/// Saves a tapped lyric word as a card in a custom deck (PLAN_M6 §4.10, L8).
struct AddToDeckSheet: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss

    let candidate: LyricAddCandidate
    /// Called with the deck's title after a successful save.
    let onSaved: (String) -> Void

    private enum Target: Hashable {
        case existing(String)
        case new
    }

    @State private var hangul = ""
    @State private var meanings = ""
    @State private var pos = PartOfSpeech.noun
    @State private var english = ""
    @State private var target: Target = .new
    @State private var newTitle = "My lyrics words"
    @State private var problems: [String] = []
    @State private var saving = false
    @State private var prepared = false

    private var decks: [VocabDeck] {
        let all = env.userDecks
        guard let last = env.settings.lastLyricsDeckID, let i = all.firstIndex(where: { $0.id.raw == last }) else { return all }
        return [all[i]] + all.enumerated().filter { $0.offset != i }.map(\.element)
    }

    private var targetFile: VocabDeckFile? {
        guard case let .existing(id) = target else { return nil }
        return env.userDeckFile(id: DeckID(id))
    }

    private var targetTitle: String {
        switch target {
        case let .existing(id): decks.first { $0.id.raw == id }?.title ?? ""
        case .new: newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    private var isDuplicate: Bool {
        guard let file = targetFile else { return false }
        let h = hangul.trimmingCharacters(in: .whitespacesAndNewlines).precomposedStringWithCanonicalMapping
        return file.entries.contains { $0.hangul.precomposedStringWithCanonicalMapping == h }
    }

    private var canSave: Bool {
        !saving && !hangul.trimmingCharacters(in: .whitespaces).isEmpty && !targetTitle.isEmpty && !isDuplicate
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Word") {
                    TextField("Hangul", text: $hangul)
                        .font(.title3)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("lyrics.add.hangul")
                    TextField("Meanings, comma-separated", text: $meanings)
                        .textInputAutocapitalization(.never)
                        .accessibilityIdentifier("lyrics.add.meanings")
                    Picker("Part of speech", selection: $pos) {
                        ForEach(PartOfSpeech.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .accessibilityIdentifier("lyrics.add.pos")
                }

                Section {
                    Text(candidate.line).font(.body)
                    TextField("English translation of the line", text: $english)
                        .accessibilityIdentifier("lyrics.add.english")
                } header: {
                    Text("Example")
                } footer: {
                    if let note = exampleNote { Text(note) }
                }

                Section {
                    Picker("Deck", selection: $target) {
                        ForEach(decks, id: \.id) { Text($0.title).tag(Target.existing($0.id.raw)) }
                        Text("+ New deck…").tag(Target.new)
                    }
                    .accessibilityIdentifier("lyrics.add.deck")
                    if target == .new {
                        TextField("Deck title", text: $newTitle)
                            .accessibilityIdentifier("lyrics.add.newDeckTitle")
                    }
                } header: {
                    Text("Deck")
                } footer: {
                    VStack(alignment: .leading, spacing: 4) {
                        if isDuplicate { Text("Already in \(targetTitle)").foregroundStyle(.red) }
                        if let ref = source { Text("Heard in: \(ref.title) · \(ref.by)") }
                    }
                }

                if !problems.isEmpty {
                    Section { ForEach(problems, id: \.self) { Text($0).font(.footnote).foregroundStyle(.red) } }
                }
            }
            .scrollContentBackground(.hidden)
            .auroraBackground(colors: Subject.korean.colors, intensity: 0.4)
            .tint(Subject.korean.accent)
            .animation(Theme.spring, value: problems)
            .navigationTitle("Add to deck")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.accessibilityIdentifier("lyrics.add.cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }
                        .disabled(!canSave)
                        .accessibilityIdentifier("lyrics.add.save")
                }
            }
            .onAppear(perform: prepare)
            .onChange(of: hangul) { _, _ in problems = [] }
        }
        .presentationDetents([.large])
    }

    // MARK: Prefill

    private func prepare() {
        guard !prepared else { return }
        prepared = true
        if let hit = candidate.hit {
            hangul = hit.hangul
        } else {
            let stripped = ScreenshotWords.stripParticle(candidate.tapped)
            hangul = stripped.isEmpty ? candidate.tapped : stripped
        }
        meanings = candidate.meaning
        pos = UserDecks.guessedPartOfSpeech(hangul: hangul, meanings: UserDecks.meanings(from: meanings))
        english = candidate.englishLine ?? ""
        if let first = decks.first { target = .existing(first.id.raw) } else { target = .new }
    }

    // MARK: Save

    /// "Heard in" reference; omitted when Spotify gave no release year the validator accepts (1990…now).
    private var source: MediaRef? {
        let t = candidate.track
        let now = Calendar(identifier: .gregorian).component(.year, from: Date())
        guard let year = t.releaseYear, (1990...now).contains(year), !t.artistLine.isEmpty else { return nil }
        return MediaRef(
            kind: .song, title: t.displayTitle, by: t.artistLine, year: year, locator: "lyrics",
            context: "Saved while reading the lyrics.", citation: "spotify:track:\(t.spotifyID)")
    }

    /// The lyric line is always kept (custom decks allow a blank English line and up to 80 Hangul, L-D10).
    private var example: VocabEntry.Example? {
        let ko = candidate.line.trimmingCharacters(in: .whitespacesAndNewlines)
        let en = english.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !ko.isEmpty, Hangul.syllableCount(ko) <= DeckValidator.userExampleMaxHangul else { return nil }
        return VocabEntry.Example(ko: ko, en: en)
    }

    private var exampleNote: String? {
        guard example == nil, Hangul.syllableCount(candidate.line) > DeckValidator.userExampleMaxHangul else { return nil }
        return "This line is too long to keep as the card's example."
    }

    private var draft: UserDecks.EntryDraft {
        UserDecks.EntryDraft(
            hangul: hangul, meanings: UserDecks.meanings(from: meanings), pos: pos,
            example: example, sources: source.map { [$0] } ?? []
        ).normalized
    }

    private func save() async {
        saving = true
        defer { saving = false }
        let base: VocabDeckFile
        switch target {
        case let .existing(id):
            guard let file = env.userDeckFile(id: DeckID(id)) else { problems = ["That deck no longer exists."]; return }
            base = file
        case .new:
            var rng = SplitMix64(seed: UInt64.random(in: .min ... .max))
            let id = UserDecks.newDeckID(existing: Set(env.catalog.decks.map(\.id.raw)), using: &rng)
            base = UserDecks.newDeck(id: id, title: targetTitle)
        }
        let d = draft
        problems = UserDecks.problems(d, in: base)
        guard problems.isEmpty else { return }
        do {
            try await env.saveUserDeck(UserDecks.adding(d, to: base))
        } catch {
            problems = ["Couldn't save: \(error.localizedDescription)"]
            return
        }
        env.settings.lastLyricsDeckID = base.deckId
        env.haptics.ok()
        onSaved(base.title)
        dismiss()
    }
}

#Preview("Add to deck") {
    let track = TrackInfo(spotifyID: "x", title: "Spring Day", titleKo: "봄날", artists: ["BTS"], releaseYear: 2017)
    return Color.clear.sheet(isPresented: .constant(true)) {
        AddToDeckSheet(
            candidate: LyricAddCandidate(
                track: track, tapped: "너를", hit: nil, meaning: "you", line: "너를 보고 싶다", englishLine: "I miss you"),
            onSaved: { _ in })
    }
    .environment(AppEnvironment.preview())
}
