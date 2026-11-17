import MemoriseCore
import SwiftUI
import UIKit

/// Persistent answer field for typed sessions. It stays mounted across cards so the keyboard
/// doesn't drop between prompts; it clears itself when `resetID` changes.
struct TypedAnswerField: View {
    let kind: AnswerMatchKind?
    /// Changes on every new card.
    let resetID: Int
    /// False while the answer is revealed (Return then means Next).
    let isEditable: Bool
    let colors: [Color]
    let onSubmit: (String) -> Void
    let onNext: () -> Void

    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 8) {
            if kind == .hangul, isEditable, !Self.hasKoreanKeyboard {
                Label("Add the Korean keyboard in Settings → General → Keyboard", systemImage: "keyboard.badge.ellipsis")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("koreanKeyboardHint")
            }
            HStack(spacing: 10) {
                TextField(placeholder, text: $text)
                    .font(.title3.weight(.semibold))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(isEditable ? .done : .next)
                    .focused($focused)
                    .onSubmit {
                        // Keep the keyboard up: SwiftUI drops focus on submit.
                        focused = true
                        if isEditable { onSubmit(text) } else { onNext() }
                    }
                    .padding(.horizontal, 16).padding(.vertical, 12)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing).opacity(focused ? 0.9 : 0.3), lineWidth: 2)
                    }
                    .accessibilityIdentifier("typedAnswerField")
                Button {
                    focused = true
                    if isEditable { onSubmit(text) } else { onNext() }
                } label: {
                    Image(systemName: isEditable ? "return" : "arrow.right")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 48, height: 48)
                        .background(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing), in: Circle())
                }
                .buttonStyle(PressableStyle(scale: 0.9))
                .disabled(isEditable && text.trimmingCharacters(in: .whitespaces).isEmpty)
                .accessibilityLabel(isEditable ? "Check answer" : "Next")
                .accessibilityIdentifier("typedSubmitButton")
            }
        }
        .onAppear { focused = true }
        .onChange(of: resetID) {
            text = ""
            focused = true
        }
    }

    private var placeholder: String {
        switch kind {
        case .hangul: "Type in Korean"
        case .english: "Type the meaning"
        case .romanization: "Type the sound (romanization)"
        case nil: "Type your answer"
        }
    }

    /// Whether a Korean keyboard is enabled on this device.
    static var hasKoreanKeyboard: Bool {
        UITextInputMode.activeInputModes.contains { $0.primaryLanguage?.hasPrefix("ko") == true }
    }
}

/// "✓ Correct" / "≈ Close: check spelling" / "✗ Wrong" with the user's input diffed against the answer.
struct VerdictBanner: View {
    let answer: AutoAnswer

    var body: some View {
        VStack(spacing: 10) {
            Label(title, systemImage: icon)
                .font(.headline.weight(.bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 16).padding(.vertical, 8)
                .background(gradient, in: Capsule())
                .accessibilityIdentifier("verdictBanner")
            if let input = answer.input, !input.isEmpty, answer.verdict != .exact {
                VStack(spacing: 4) {
                    HStack(spacing: 6) {
                        Text("Yours").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        diffText(input)
                    }
                    HStack(spacing: 6) {
                        Text("Answer").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        Text(answer.expected).font(.title3.weight(.semibold))
                    }
                }
                .accessibilityElement(children: .combine)
            } else if let chosen = answer.chosen, !chosen.isCorrect {
                Text("You chose \(chosen.label)").font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }

    private func diffText(_ input: String) -> Text {
        AnswerMatcher.diff(input, against: answer.expected).reduce(Text("")) { acc, item in
            acc + Text(String(item.character))
                .font(.title3.weight(.semibold))
                .foregroundColor(item.matches ? .primary : Theme.rose)
                .underline(!item.matches, color: Theme.rose)
        }
    }

    private var title: String {
        if let o = answer.override { return o ? "Marked correct" : "Marked wrong" }
        switch answer.verdict {
        case .exact: return "Correct"
        case .close: return answer.exactRequired ? "Close — but spelling counts" : "Close: check spelling"
        case .wrong: return answer.input == "" ? "Not answered" : "Wrong"
        }
    }

    private var icon: String {
        if let o = answer.override { return o ? "checkmark" : "xmark" }
        switch answer.verdict {
        case .exact: return "checkmark"
        case .close: return "approximately.equal"
        case .wrong: return "xmark"
        }
    }

    private var gradient: LinearGradient {
        if answer.override == nil, answer.verdict == .close {
            return LinearGradient(colors: [Theme.amber, .orange], startPoint: .leading, endPoint: .trailing)
        }
        return answer.correct ? Theme.correctGradient : Theme.wrongGradient
    }
}

/// Grid of 2–4 options for `choice` mode.
struct ChoiceGrid: View {
    let choices: [AnswerChoice]
    let colors: [Color]
    let onChoose: (AnswerChoice) -> Void

    var body: some View {
        let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(Array(choices.enumerated()), id: \.element) { i, choice in
                Button { onChoose(choice) } label: {
                    Text(choice.label)
                        .font(.title2.weight(.bold))
                        .lineLimit(1).minimumScaleFactor(0.5)
                        .frame(maxWidth: .infinity, minHeight: 60)
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .strokeBorder(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing).opacity(0.5), lineWidth: 2)
                        }
                }
                .buttonStyle(PressableStyle(scale: 0.95))
                .accessibilityIdentifier("choice\(i)")
                .keyboardShortcut(KeyEquivalent(Character("\(i + 1)")), modifiers: [])
            }
        }
    }
}

#Preview("Typed field") {
    VStack(spacing: 30) {
        TypedAnswerField(kind: .hangul, resetID: 0, isEditable: true, colors: Subject.korean.colors, onSubmit: { _ in }, onNext: {})
        VerdictBanner(answer: AutoAnswer(verdict: .close, input: "핵교", chosen: nil, expected: "학교", exactRequired: false))
        ChoiceGrid(choices: [.init(label: "책은", isCorrect: true), .init(label: "책는", isCorrect: false)], colors: Subject.korean.colors) { _ in }
    }
    .padding()
}
