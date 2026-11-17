import MemoriseCore
import SwiftUI

/// Edit a user deck: title, subtitle, words; delete the deck (PLAN_M4 M4-8).
struct UserDeckEditorView: View {
    let deckID: DeckID

    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var subtitle = ""
    @State private var editing: EntryEditTarget?
    @State private var confirmDelete = false
    @State private var errorMessage: String?
    @State private var importing = false

    private var file: VocabDeckFile? { env.userDeckFile(id: deckID) }

    var body: some View {
        Form {
            if let file {
                Section("Deck") {
                    TextField("Title", text: $title)
                        .onSubmit { Task { await rename() } }
                        .accessibilityIdentifier("userDeckTitleField")
                    TextField("Subtitle (optional)", text: $subtitle)
                        .onSubmit { Task { await rename() } }
                        .accessibilityIdentifier("userDeckSubtitleField")
                }
                Section {
                    ForEach(file.entries) { e in
                        Button { editing = .existing(e) } label: { EntryRow(entry: e) }
                            .accessibilityIdentifier("userEntry.\(e.id)")
                    }
                    .onDelete { offsets in
                        let ids = offsets.map { file.entries[$0].id }
                        Task { await update { ids.reduce($0) { UserDecks.deleting($1, from: $0) } } }
                    }
                    Button { editing = .new } label: {
                        Label("Add word", systemImage: "plus.circle.fill")
                    }
                    .accessibilityIdentifier("userDeckAddWordButton")
                } header: {
                    Text("Words (\(file.entries.count))")
                } footer: {
                    Text("Swipe left to delete a word.")
                }
                if deckID.raw == UserDecks.aionDeckID {
                    Section {
                        Button { importing = true } label: {
                            Label("Add from screenshot", systemImage: "text.viewfinder")
                        }
                        .accessibilityIdentifier("userDeckScreenshotButton")
                    }
                }
                Section {
                    Button("Delete deck", role: .destructive) { confirmDelete = true }
                        .accessibilityIdentifier("userDeckDeleteButton")
                } footer: {
                    Text("Deleting a deck also deletes its progress.")
                }
            } else {
                ContentUnavailableView("Deck not found", systemImage: "rectangle.stack.badge.minus")
            }
        }
        .navigationTitle(title.isEmpty ? "Deck" : title)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            title = file?.title ?? ""
            subtitle = file?.subtitle ?? ""
        }
        .onDisappear { Task { await rename() } }
        .sheet(item: $editing) { target in
            if let file {
                NavigationStack {
                    UserEntryEditorView(target: target, file: file) { draft in
                        Task {
                            await update { f in
                                switch target {
                                case .new: UserDecks.adding(draft, to: f)
                                case let .existing(e): UserDecks.updating(e.id, with: draft, in: f)
                                }
                            }
                        }
                        editing = nil
                    }
                }
            }
        }
        .sheet(isPresented: $importing) {
            NavigationStack { ScreenshotImportView(deckID: deckID) }
        }
        .confirmationDialog("Delete “\(file?.title ?? "")”?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete deck and progress", role: .destructive) { Task { await deleteDeck() } }
        } message: {
            Text("This can't be undone.")
        }
        .alert("Couldn't save", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func update(_ change: (VocabDeckFile) -> VocabDeckFile) async {
        guard let file else { return }
        do {
            try await env.saveUserDeck(change(file))
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func rename() async {
        guard let file else { return }
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let s = subtitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { title = file.title; return }
        guard t != file.title || s != file.subtitle else { return }
        await update { UserDecks.renaming($0, title: t, subtitle: s) }
    }

    private func deleteDeck() async {
        do {
            try await env.deleteUserDeck(id: deckID)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// Which entry the sheet edits.
enum EntryEditTarget: Identifiable, Hashable {
    case new
    case existing(VocabEntry)

    var id: String {
        switch self {
        case .new: "new"
        case let .existing(e): e.id
        }
    }
}

private struct EntryRow: View {
    let entry: VocabEntry

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.hangul).font(.headline).foregroundStyle(.primary)
                Text(entry.meaningText).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Text(entry.pos).font(.caption).foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
    }
}

/// Add or edit one word.
struct UserEntryEditorView: View {
    let target: EntryEditTarget
    let file: VocabDeckFile
    let onSave: (UserDecks.EntryDraft) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var hangul = ""
    @State private var meanings = ""
    @State private var pos = PartOfSpeech.noun
    @State private var romanization = ""
    @State private var exampleKo = ""
    @State private var exampleEn = ""
    @State private var tags = ""
    @State private var problems: [String] = []

    var body: some View {
        Form {
            Section {
                TextField("Hangul (e.g. 사과)", text: $hangul)
                    .font(.title3)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("userEntryHangulField")
                TextField("Meanings, comma-separated", text: $meanings)
                    .textInputAutocapitalization(.never)
                    .accessibilityIdentifier("userEntryMeaningsField")
                Picker("Part of speech", selection: $pos) {
                    ForEach(PartOfSpeech.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .accessibilityIdentifier("userEntryPosPicker")
            } footer: {
                if pos.isPredicate { Text("Verbs and adjectives use the dictionary form ending in 다.") }
            }
            Section("Optional") {
                TextField("Romanization", text: $romanization)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("userEntryRomanizationField")
                TextField("Example (Korean)", text: $exampleKo)
                    .accessibilityIdentifier("userEntryExampleKoField")
                TextField("Example (English)", text: $exampleEn)
                    .accessibilityIdentifier("userEntryExampleEnField")
                TextField("Tags, comma-separated", text: $tags)
                    .textInputAutocapitalization(.never)
                    .accessibilityIdentifier("userEntryTagsField")
            }
            if !problems.isEmpty {
                Section {
                    ForEach(problems, id: \.self) { Text($0).font(.footnote).foregroundStyle(.red) }
                }
            }
        }
        .navigationTitle(target == .new ? "New word" : "Edit word")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }.accessibilityIdentifier("userEntryCancelButton")
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save", action: save)
                    .disabled(hangul.isEmpty || meanings.isEmpty)
                    .accessibilityIdentifier("userEntrySaveButton")
            }
        }
        .onAppear(perform: fill)
    }

    private var draft: UserDecks.EntryDraft {
        UserDecks.EntryDraft(
            hangul: hangul, meanings: UserDecks.meanings(from: meanings), pos: pos, romanization: romanization,
            example: exampleKo.isEmpty && exampleEn.isEmpty ? nil : VocabEntry.Example(ko: exampleKo, en: exampleEn),
            tags: UserDecks.meanings(from: tags)
        ).normalized
    }

    private func fill() {
        guard case let .existing(e) = target else { return }
        hangul = e.hangul
        meanings = e.meanings.joined(separator: ", ")
        pos = e.partOfSpeech ?? .noun
        romanization = e.romanization
        exampleKo = e.example?.ko ?? ""
        exampleEn = e.example?.en ?? ""
        tags = e.tags.joined(separator: ", ")
    }

    private func save() {
        let d = draft
        problems = UserDecks.problems(d, in: file)
        guard problems.isEmpty else { return }
        onSave(d)
    }
}

#Preview("Deck editor") {
    NavigationStack { UserDeckEditorView(deckID: "user.0000abcd") }
        .environment(AppEnvironment.preview())
}

#Preview("Word editor") {
    NavigationStack {
        UserEntryEditorView(target: .new, file: UserDecks.newDeck(id: "user.0000abcd", title: "Mine")) { _ in }
    }
}
