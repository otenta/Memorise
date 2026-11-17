import MemoriseCore
import PhotosUI
import SwiftUI

/// AION 2 screenshot → words for a user deck (PLAN_M4 M4-9). The screenshot is never stored.
struct ScreenshotImportView: View {
    let deckID: DeckID

    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    @State private var pick: PhotosPickerItem?
    @State private var phase = Phase.idle
    @State private var candidates: [Candidate] = []
    @State private var known: [String] = []
    @State private var errorMessage: String?

    enum Phase { case idle, reading, review }

    struct Candidate: Identifiable, Hashable {
        var id: String { hangul }
        let hangul: String
        var selected = true
        var meaning = ""
        var romanization = ""
    }

    private var selected: [Candidate] { candidates.filter(\.selected) }
    private var canSave: Bool { !selected.isEmpty && selected.allSatisfy { !UserDecks.meanings(from: $0.meaning).isEmpty } }

    var body: some View {
        Form {
            Section {
                PhotosPicker(selection: $pick, matching: .images, photoLibrary: .shared()) {
                    Label(phase == .idle ? "Choose a screenshot" : "Choose another screenshot", systemImage: "photo.on.rectangle")
                }
                .accessibilityIdentifier("screenshotPicker")
                if phase == .reading {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Reading Korean text…").foregroundStyle(.secondary)
                    }
                }
            } footer: {
                Text("Text is recognised on this device. The screenshot isn't saved; only the words you keep are.")
            }

            if phase == .review {
                if candidates.isEmpty {
                    Section { Text("No new Korean words found.").foregroundStyle(.secondary) }
                } else {
                    Section {
                        ForEach($candidates) { $c in
                            CandidateRow(candidate: $c)
                        }
                    } header: {
                        Text("New words (\(selected.count)/\(candidates.count) selected)")
                    } footer: {
                        Text("Type a meaning for each selected word. Particles like 을/를/에서 were removed; check each word.")
                    }
                }
                if !known.isEmpty {
                    Section {
                        DisclosureGroup("Already known (\(known.count))") {
                            Text(known.joined(separator: " · ")).font(.callout).foregroundStyle(.secondary)
                        }
                        .accessibilityIdentifier("screenshotKnownWords")
                    }
                }
            }
        }
        .navigationTitle("Add from screenshot")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }.accessibilityIdentifier("screenshotCancelButton")
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Add \(selected.count)") { Task { await save() } }
                    .disabled(!canSave)
                    .accessibilityIdentifier("screenshotSaveButton")
            }
        }
        .onChange(of: pick) { _, item in
            guard let item else { return }
            Task { await read(item) }
        }
        .alert("Couldn't add words", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func read(_ item: PhotosPickerItem) async {
        phase = .reading
        defer { pick = nil }
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else { throw KoreanTextExtractor.ExtractError.unreadableImage }
            let lines = try await KoreanTextExtractor.lines(fromImageData: data)
            let knownHangul = Set(env.catalog.vocabDecks.flatMap { $0.entries.map(\.hangul) })
            let result = ScreenshotWords.extract(lines: lines, knownHangul: knownHangul)
            // Keep what the user already typed for words that show up again.
            let previous = Dictionary(candidates.map { ($0.hangul, $0) }, uniquingKeysWith: { a, _ in a })
            candidates = result.words.map { previous[$0] ?? Candidate(hangul: $0) }
            known = result.known
            phase = .review
        } catch {
            errorMessage = error.localizedDescription
            phase = candidates.isEmpty ? .idle : .review
        }
    }

    private func save() async {
        guard var file = env.userDeckFile(id: deckID) else { errorMessage = "Deck not found"; return }
        for c in selected {
            let draft = UserDecks.EntryDraft(
                hangul: c.hangul, meanings: UserDecks.meanings(from: c.meaning), pos: .noun, romanization: c.romanization, tags: ["aion2"]
            ).normalized
            let problems = UserDecks.problems(draft, in: file)
            guard problems.isEmpty else { errorMessage = "\(c.hangul): \(problems.joined(separator: "; "))"; return }
            file = UserDecks.adding(draft, to: file)
        }
        do {
            try await env.saveUserDeck(file)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct CandidateRow: View {
    @Binding var candidate: ScreenshotImportView.Candidate

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: $candidate.selected) {
                Text(candidate.hangul).font(.title3.weight(.semibold))
            }
            .accessibilityIdentifier("screenshotWordToggle.\(candidate.hangul)")
            if candidate.selected {
                TextField("Meaning (required)", text: $candidate.meaning)
                    .textInputAutocapitalization(.never)
                    .accessibilityIdentifier("screenshotMeaningField.\(candidate.hangul)")
                TextField("Romanization (optional)", text: $candidate.romanization)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.subheadline)
                    .accessibilityIdentifier("screenshotRomanizationField.\(candidate.hangul)")
            }
        }
        .padding(.vertical, 2)
    }
}

#Preview("Screenshot import") {
    NavigationStack { ScreenshotImportView(deckID: DeckID(UserDecks.aionDeckID)) }
        .environment(AppEnvironment.preview())
}
