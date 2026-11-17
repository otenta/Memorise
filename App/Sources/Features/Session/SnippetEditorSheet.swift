import MemoriseCore
import SwiftUI

/// Add / edit / delete the user's own on-device snippet for a vocab entry (M5 K4).
struct SnippetEditorSheet: View {
    let entry: VocabEntry

    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var source = ""
    @State private var saving = false
    @State private var errorMessage: String?
    @State private var confirmDelete = false
    @FocusState private var focused: Field?

    private enum Field { case text, source }

    private var existing: PersonalSnippet? { env.personalSnippet(for: entry.id) }
    private var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var limit: Int { PersonalSnippet.maxTextLength }
    private var hasChanges: Bool {
        trimmed != (existing?.text ?? "") ||
            source.trimmingCharacters(in: .whitespacesAndNewlines) != (existing?.source ?? "")
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    header
                    editorCard
                    sourceField
                    privacyNote
                    if existing != nil { deleteButton }
                }
                .padding(20)
            }
            .scrollDismissesKeyboard(.interactively)
            .auroraBackground(colors: [Theme.mint, Theme.teal], intensity: 0.55)
            .navigationTitle(existing == nil ? "New snippet" : "My snippet")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .accessibilityIdentifier("snippetCancelButton")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button { Task { await save() } } label: {
                        if saving { ProgressView() } else { Text("Save").bold() }
                    }
                    .disabled(trimmed.isEmpty || !hasChanges || saving)
                    .accessibilityIdentifier("snippetSaveButton")
                }
            }
            .alert("Couldn't save", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
            .confirmationDialog("Delete this snippet?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) { Task { await delete() } }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(32)
        .interactiveDismissDisabled(hasChanges && !trimmed.isEmpty)
        .onAppear {
            text = existing?.text ?? ""
            source = existing?.source ?? ""
            focused = .text
        }
    }

    // MARK: Pieces

    private var header: some View {
        VStack(spacing: 4) {
            Text(entry.hangul)
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(Subject.korean.gradient)
            Text(entry.meaningText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private var editorCard: some View {
        VStack(alignment: .trailing, spacing: 8) {
            ZStack(alignment: .topLeading) {
                if text.isEmpty {
                    Text("A lyric line, a quote, or a note to remember it by…")
                        .foregroundStyle(.tertiary)
                        .padding(.top, 8).padding(.leading, 5)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $text)
                    .focused($focused, equals: .text)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 120)
                    .onChange(of: text) { _, new in
                        if new.count > limit { text = String(new.prefix(limit)) }
                    }
                    .accessibilityLabel("Snippet text")
                    .accessibilityIdentifier("snippetTextEditor")
            }
            CharacterRing(count: text.count, limit: limit)
        }
        .padding(14)
        .glassCard(radius: 22, tint: Theme.teal)
    }

    private var sourceField: some View {
        HStack(spacing: 10) {
            Image(systemName: "music.note.list")
                .foregroundStyle(Theme.teal)
            TextField("Where it's from (optional)", text: $source)
                .focused($focused, equals: .source)
                .submitLabel(.done)
                .onSubmit { focused = nil }
                .accessibilityIdentifier("snippetSourceField")
        }
        .padding(14)
        .glassCard(radius: 18, tint: Theme.teal)
    }

    private var privacyNote: some View {
        Label("Stays on this device. It's only included when you export your data yourself.", systemImage: "lock.fill")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var deleteButton: some View {
        Button(role: .destructive) { confirmDelete = true } label: {
            Label("Delete snippet", systemImage: "trash")
                .font(.body.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 50)
                .background(Theme.rose.opacity(0.12), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(PressableStyle())
        .foregroundStyle(Theme.rose)
        .accessibilityIdentifier("snippetDeleteButton")
    }

    // MARK: Actions

    private func save() async {
        saving = true
        defer { saving = false }
        do {
            try await env.savePersonalSnippet(entryID: entry.id, text: trimmed, source: source)
            env.haptics.grade(correct: true)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func delete() async {
        do {
            try await env.deletePersonalSnippet(entryID: entry.id)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// Small ring that fills as the snippet approaches its limit; turns amber, then rose.
private struct CharacterRing: View {
    let count: Int
    let limit: Int

    private var fraction: Double { min(1, Double(count) / Double(limit)) }
    private var color: Color { fraction >= 1 ? Theme.rose : fraction > 0.85 ? Theme.amber : Theme.teal }

    var body: some View {
        HStack(spacing: 6) {
            if fraction > 0.7 {
                Text("\(limit - count)")
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(color)
                    .contentTransition(.numericText(value: Double(limit - count)))
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
            }
            ZStack {
                Circle().stroke(.primary.opacity(0.1), lineWidth: 3)
                Circle()
                    .trim(from: 0, to: fraction)
                    .stroke(color, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: 20, height: 20)
        }
        .animation(Theme.spring, value: count)
        .accessibilityElement()
        .accessibilityLabel("\(limit - count) characters left")
    }
}

#Preview("Snippet editor") {
    Color.clear.sheet(isPresented: .constant(true)) {
        SnippetEditorSheet(entry: .previewMedia)
    }
    .environment(AppEnvironment.preview())
}
