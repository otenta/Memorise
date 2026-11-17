import MemoriseCore
import SwiftUI

// MARK: - Panel (M5 K3/K4)

/// "In a scene" / "Heard in" / "My snippet" panel under a media phrase's answer.
/// Plain text only — no links anywhere (PLAN_M5 §2).
struct MediaSnippetView: View {
    let entry: VocabEntry
    /// Session-hosted editor (pauses the session). `nil` = present a local sheet (previews, outside sessions).
    var onEditSnippet: (@MainActor (VocabEntry) -> Void)?

    @Environment(AppEnvironment.self) private var env
    @State private var localEditor: SnippetEditTarget?

    /// Only media-style entries get the panel, so existing decks look unchanged.
    static func shouldShow(for entry: VocabEntry) -> Bool {
        !entry.dialogue.isEmpty || !entry.sources.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            if !entry.dialogue.isEmpty {
                PanelSection(title: "In a scene", systemImage: "bubble.left.and.bubble.right.fill", colors: [Theme.coral, Theme.pink]) {
                    VStack(spacing: 10) {
                        ForEach(Array(entry.dialogue.enumerated()), id: \.offset) { i, line in
                            DialogueBubble(line: line, index: i)
                                .appearAnimation(index: i + 1)
                        }
                    }
                }
            }
            if !entry.sources.isEmpty {
                PanelSection(title: "Heard in", systemImage: "sparkles", colors: [Theme.indigo, Theme.violet]) {
                    VStack(spacing: 10) {
                        ForEach(Array(entry.sources.enumerated()), id: \.offset) { i, ref in
                            MediaSourceRow(ref: ref, index: i)
                                .appearAnimation(index: entry.dialogue.count + i + 1)
                        }
                    }
                }
            }
            PanelSection(title: "My snippet", systemImage: "pencil.and.scribble", colors: [Theme.mint, Theme.teal]) {
                MySnippetCard(snippet: env.personalSnippet(for: entry.id), edit: edit)
                    .appearAnimation(index: entry.dialogue.count + entry.sources.count + 1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("mediaSnippet")
        .sheet(item: $localEditor) { SnippetEditorSheet(entry: $0.entry) }
    }

    private func edit() {
        if let onEditSnippet { onEditSnippet(entry) } else { localEditor = SnippetEditTarget(entry: entry) }
    }
}

// MARK: - Section chrome

private struct PanelSection<Content: View>: View {
    let title: String
    let systemImage: String
    let colors: [Color]
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 24, height: 24)
                    .background(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing),
                                in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .shadow(color: colors[0].opacity(0.35), radius: 4, y: 2)
                Text(title.uppercased())
                    .font(.system(.caption, design: .rounded, weight: .heavy))
                    .tracking(1.2)
                    .foregroundStyle(.secondary)
                Rectangle()
                    .fill(LinearGradient(colors: [colors[0].opacity(0.35), .clear], startPoint: .leading, endPoint: .trailing))
                    .frame(height: 1)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            content
        }
    }
}

// MARK: - Dialogue

/// A chat bubble: A and C on the left (different tints), B on the right.
private struct DialogueBubble: View {
    let line: DialogueLine
    let index: Int
    @Environment(AppEnvironment.self) private var env

    private var isRight: Bool { line.speaker == "B" }

    private var colors: [Color] {
        switch line.speaker {
        case "B": [Theme.violet, Theme.indigo]
        case "C": [Theme.teal, Theme.mint]
        default: [Theme.coral, Theme.pink]
        }
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if isRight { Spacer(minLength: 36) } else { avatar }
            bubble
            if isRight { avatar } else { Spacer(minLength: 36) }
        }
    }

    private var avatar: some View {
        Text(line.speaker)
            .font(.system(.caption, design: .rounded, weight: .heavy))
            .foregroundStyle(.white)
            .frame(width: 28, height: 28)
            .background(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing), in: Circle())
            .overlay(Circle().strokeBorder(.white.opacity(0.35), lineWidth: 1))
            .accessibilityHidden(true)
    }

    private var bubble: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(line.ko)
                    .font(.body.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                Text(line.en)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Speaker \(line.speaker): \(line.ko), meaning \(line.en)")
            SpeakIconButton(text: line.ko, colors: colors, size: 32, label: "Play line")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background {
            BubbleShape(tailOnRight: isRight)
                .fill(LinearGradient(colors: colors.map { $0.opacity(0.16) }, startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay(BubbleShape(tailOnRight: isRight).stroke(colors[0].opacity(0.28), lineWidth: 1))
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("dialogueLine.\(index)")
    }
}

/// Rounded bubble with a smaller corner where the tail would be.
private struct BubbleShape: Shape {
    let tailOnRight: Bool

    func path(in rect: CGRect) -> Path {
        let big: CGFloat = 18, small: CGFloat = 5
        return Path(roundedRect: rect, cornerRadii: RectangleCornerRadii(
            topLeading: big,
            bottomLeading: tailOnRight ? big : small,
            bottomTrailing: tailOnRight ? small : big,
            topTrailing: big
        ), style: .continuous)
    }
}

// MARK: - Sources

private struct MediaSourceRow: View {
    let ref: MediaRef
    let index: Int

    private var icon: String {
        switch ref.kind {
        case .song: "music.note"
        case .drama, .show: "tv"
        case .film: "film"
        }
    }

    private var colors: [Color] {
        switch ref.kind {
        case .song: [Theme.violet, Theme.pink]
        case .drama: [Theme.indigo, Theme.teal]
        case .show: [Theme.amber, Theme.coral]
        case .film: [Theme.teal, Theme.indigo]
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 42, height: 42)
                .background(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing),
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .shadow(color: colors[0].opacity(0.4), radius: 6, y: 3)
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(ref.title).font(.headline)
                    if let ko = ref.titleKo, !ko.isEmpty {
                        Text(ko).font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 6) {
                    Text("\(ref.by) · \(String(ref.year))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if !ref.locator.isEmpty {
                        Text(ref.locator)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(colors[0])
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(colors[0].opacity(0.14), in: Capsule())
                    }
                }
                if !ref.context.isEmpty {
                    Text(ref.context)
                        .font(.callout)
                        .foregroundStyle(.primary.opacity(0.85))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.fill.quaternary, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(colors[0].opacity(0.18), lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityIdentifier("mediaSource.\(index)")
    }

    private var accessibilityText: String {
        var parts = ["Heard in \(ref.title) by \(ref.by), \(ref.year)"]
        if !ref.locator.isEmpty { parts.append(ref.locator) }
        if !ref.context.isEmpty { parts.append(ref.context) }
        return parts.joined(separator: ", ")
    }
}

// MARK: - My snippet

private struct MySnippetCard: View {
    let snippet: PersonalSnippet?
    let edit: () -> Void

    var body: some View {
        Group {
            if let snippet {
                saved(snippet)
            } else {
                addButton
            }
        }
        .animation(Theme.spring, value: snippet)
    }

    private func saved(_ s: PersonalSnippet) -> some View {
        Button(action: edit) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "quote.opening")
                    .font(.title3.weight(.black))
                    .foregroundStyle(LinearGradient(colors: [Theme.mint, Theme.teal], startPoint: .top, endPoint: .bottom))
                VStack(alignment: .leading, spacing: 6) {
                    Text(s.text)
                        .font(.body)
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    if let source = s.source {
                        Text("— \(source)").font(.subheadline.italic()).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "pencil.circle.fill")
                    .font(.title2)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Theme.teal)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                LinearGradient(colors: [Theme.mint.opacity(0.14), Theme.teal.opacity(0.08)], startPoint: .topLeading, endPoint: .bottomTrailing),
                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
            )
            .overlay(alignment: .leading) {
                Capsule()
                    .fill(LinearGradient(colors: [Theme.mint, Theme.teal], startPoint: .top, endPoint: .bottom))
                    .frame(width: 4)
                    .padding(.vertical, 12)
            }
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(PressableStyle(scale: 0.98))
        .transition(.scale(scale: 0.92).combined(with: .opacity))
        .accessibilityLabel("My snippet: \(s.text)\(s.source.map { ", from \($0)" } ?? "")")
        .accessibilityHint("Edit your snippet")
        .accessibilityIdentifier("editSnippetButton")
    }

    private var addButton: some View {
        Button(action: edit) {
            Label("Add your own snippet", systemImage: "plus.circle.fill")
                .font(.subheadline.weight(.semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Theme.teal)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(Theme.teal.opacity(0.06), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Theme.teal.opacity(0.45), style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
                )
                .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(PressableStyle(scale: 0.97))
        .transition(.scale(scale: 0.92).combined(with: .opacity))
        .accessibilityIdentifier("addSnippetButton")
    }
}

// MARK: - Shared bits

/// Small gradient 🔊 button that speaks Korean text.
struct SpeakIconButton: View {
    let text: String
    var colors: [Color] = Subject.korean.colors
    var size: CGFloat = 40
    var label = "Play pronunciation"
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        Button {
            env.speech.speak(text, rate: env.settings.speechRate)
        } label: {
            Image(systemName: "speaker.wave.2.fill")
                .font(.system(size: size * 0.42, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: size, height: size)
                .background(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing), in: Circle())
                .shadow(color: colors.last!.opacity(0.35), radius: 5, y: 2)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle(scale: 0.86))
        .accessibilityLabel(label)
        .accessibilityIdentifier("speakButton")
    }
}

/// "casual" / "polite" / "formal" pill.
struct RegisterChip: View {
    let register: Register

    private var color: Color {
        switch register {
        case .casual: Theme.mint
        case .polite: Theme.amber
        case .formal: Theme.indigo
        }
    }

    private var icon: String {
        switch register {
        case .casual: "face.smiling"
        case .polite: "hands.clap"
        case .formal: "building.columns"
        }
    }

    var body: some View {
        Label(register.rawValue, systemImage: icon)
            .font(.system(.caption, design: .rounded, weight: .bold))
            .foregroundStyle(color)
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(color.opacity(0.15), in: Capsule())
            .overlay(Capsule().strokeBorder(color.opacity(0.3), lineWidth: 1))
            .accessibilityLabel("Register: \(register.rawValue)")
    }
}

// MARK: - Preview data

extension VocabEntry {
    static let previewMedia = VocabEntry(
        id: "ko.media.preview", hangul: "보고 싶어", romanization: "bogo sipeo", meanings: ["I miss you"],
        pos: "expression", rank: 1, tags: ["romance"],
        notes: "Polite: 보고 싶어요.",
        register: .casual,
        dialogue: [
            DialogueLine(speaker: "A", ko: "왜 전화했어?", en: "Why did you call?"),
            DialogueLine(speaker: "B", ko: "그냥… 보고 싶어.", en: "Just… I miss you."),
        ],
        sources: [
            MediaRef(kind: .song, title: "Example Song", titleKo: "예시 노래", by: "Example Artist", year: 2024,
                     locator: "chorus", context: "Sung softly as the bridge drops away.", citation: "owner"),
            MediaRef(kind: .drama, title: "Example Drama", by: "Example Network", year: 2023,
                     locator: "S1 E4", context: "Whispered over the phone at the end of the episode.", citation: "owner"),
        ]
    )

    static let previewDialogueOnly = VocabEntry(
        id: "ko.media.preview2", hangul: "괜찮아", romanization: "gwaenchana", meanings: ["it's okay"],
        pos: "expression", rank: 2, register: .casual,
        dialogue: [
            DialogueLine(speaker: "A", ko: "미안해, 늦었어.", en: "Sorry, I'm late."),
            DialogueLine(speaker: "B", ko: "괜찮아.", en: "It's okay."),
            DialogueLine(speaker: "C", ko: "나도 방금 왔어.", en: "I just got here too."),
        ]
    )
}

#Preview("Panel · dialogue + 2 sources") {
    ScrollView { MediaSnippetView(entry: .previewMedia).padding() }
        .background { AuroraBackground(colors: Subject.korean.colors) }
        .environment(AppEnvironment.preview())
}

#Preview("Panel · dialogue only") {
    ScrollView { MediaSnippetView(entry: .previewDialogueOnly).padding() }
        .environment(AppEnvironment.preview())
}

#Preview("Panel · dark") {
    ScrollView { MediaSnippetView(entry: .previewMedia).padding() }
        .background { AuroraBackground(colors: Subject.korean.colors) }
        .preferredColorScheme(.dark)
        .environment(AppEnvironment.preview())
}

#Preview("Panel · largest type") {
    ScrollView { MediaSnippetView(entry: .previewMedia).padding() }
        .dynamicTypeSize(.accessibility5)
        .environment(AppEnvironment.preview())
}

#Preview("Panel · landscape", traits: .landscapeLeft) {
    ScrollView { MediaSnippetView(entry: .previewMedia).padding() }
        .environment(AppEnvironment.preview())
}
