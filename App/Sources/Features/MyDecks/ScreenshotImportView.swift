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
                if phase != .review {
                    ScanHero(reading: phase == .reading)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }
            }
            Section {
                // Computed outside the Sendable label closure, which can't read main-actor state (R5-6c).
                let pickerTitle = phase == .idle ? "Choose a screenshot" : "Choose another screenshot"
                PhotosPicker(selection: $pick, matching: .images, photoLibrary: .shared()) {
                    Label(pickerTitle, systemImage: "photo.on.rectangle.angled")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .background(LinearGradient(colors: [Theme.indigo, Theme.violet], startPoint: .leading, endPoint: .trailing),
                                    in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .shadow(color: Theme.violet.opacity(0.35), radius: 8, y: 4)
                }
                .buttonStyle(PressableStyle())
                .disabled(phase == .reading)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .accessibilityIdentifier("screenshotPicker")
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
        .scrollContentBackground(.hidden)
        .auroraBackground(colors: [Theme.indigo, Theme.pink], intensity: 0.45)
        .tint(Theme.indigo)
        .animation(Theme.softSpring, value: phase)
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
            let meanings = UserDecks.meanings(from: c.meaning)
            let draft = UserDecks.EntryDraft(
                hangul: c.hangul, meanings: meanings, pos: UserDecks.guessedPartOfSpeech(hangul: c.hangul, meanings: meanings),
                romanization: c.romanization, tags: ["aion2"]
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

/// Illustration: a phone frame with Hangul lines; a scan beam sweeps while reading.
private struct ScanHero: View {
    let reading: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var sweep = false

    var body: some View {
        VStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(.regularMaterial)
                    .frame(width: 120, height: 160)
                    .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Theme.violet.opacity(0.35), lineWidth: 1.5))
                VStack(alignment: .leading, spacing: 9) {
                    ForEach(["퀘스트 완료", "보상 받기", "인벤토리", "장비 강화"], id: \.self) { t in
                        Text(t)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Subject.korean.gradient)
                    }
                }
                .frame(width: 96, alignment: .leading)
                if reading && !reduceMotion {
                    LinearGradient(colors: [.clear, Theme.mint.opacity(0.55), .clear], startPoint: .top, endPoint: .bottom)
                        .frame(width: 120, height: 28)
                        .offset(y: sweep ? 66 : -66)
                        .blendMode(.plusLighter)
                        .onAppear {
                            sweep = false
                            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) { sweep = true }
                        }
                        .transition(.opacity)
                }
                Image(systemName: "text.viewfinder")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 52, height: 52)
                    .background(LinearGradient(colors: [Theme.indigo, Theme.violet], startPoint: .topLeading, endPoint: .bottomTrailing), in: Circle())
                    .shadow(color: Theme.violet.opacity(0.4), radius: 8, y: 4)
                    .symbolEffect(.pulse, options: .repeating, isActive: reading && !reduceMotion)
                    .offset(x: 62, y: 72)
            }
            .padding(.bottom, 14)
            Text(reading ? "Reading Korean text…" : "Turn a game screenshot into words")
                .font(.headline)
                .contentTransition(.opacity)
            if !reading {
                Text("Pick an AION 2 screenshot. New words show up here for you to keep.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.vertical, 18)
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

private struct CandidateRow: View {
    @Binding var candidate: ScreenshotImportView.Candidate

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: $candidate.selected.animation(Theme.spring)) {
                Text(candidate.hangul)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(candidate.selected ? AnyShapeStyle(Subject.korean.gradient) : AnyShapeStyle(.secondary))
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
