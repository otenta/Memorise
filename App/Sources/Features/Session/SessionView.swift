import MemoriseCore
import SwiftUI
import UIKit

/// Full-screen session (§11.3): prompt → reveal → grade, until the summary.
struct SessionView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    @State private var vm: SessionViewModel?
    let deck: any Deck
    let config: SessionConfig

    var body: some View {
        Group {
            if let vm {
                SessionContent(vm: vm, onDone: { dismiss() })
            } else {
                ProgressView()
            }
        }
        .task {
            guard vm == nil else { return }
            let model = SessionViewModel(env: env, deck: deck, config: config)
            vm = model
            await model.start()
        }
    }
}

private struct SessionContent: View {
    @Bindable var vm: SessionViewModel
    let onDone: () -> Void

    @Environment(AppEnvironment.self) private var env
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @FocusState private var keyboardFocused: Bool
    @State private var confirmQuit = false
    @State private var dragOffset: CGFloat = 0
    /// False during the grade lockout: grade buttons are dimmed and not hit-testable.
    @State private var gradeEnabled = true

    var body: some View {
        Group {
            if case let .finished(summary) = vm.state {
                NavigationStack {
                    SummaryView(summary: summary, deck: vm.deck, saveFailures: vm.saveFailures)
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Done", action: onDone).accessibilityIdentifier("doneButton")
                            }
                        }
                }
            } else if let error = vm.loadError {
                ContentUnavailableView("Couldn't start", systemImage: "exclamationmark.triangle", description: Text(error))
                    .overlay(alignment: .topTrailing) { Button("Close", action: onDone).padding() }
            } else {
                running
            }
        }
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            env.speech.stop()
            env.speech.deactivate()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { vm.pause() } else { keyboardFocused = true }
        }
    }

    // MARK: Running session

    private var running: some View {
        VStack(spacing: 0) {
            topBar
            ZStack {
                switch vm.state {
                case let .prompting(p):
                    promptState(p)
                        .transition(.identity)
                case let .revealed(p, ms):
                    revealState(p, responseMs: ms)
                        .transition(.asymmetric(insertion: .opacity, removal: .identity))
                case let .paused(p, _):
                    pausedOverlay(p)
                default:
                    ProgressView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: phaseKey)
        }
        .focusable()
        .focused($keyboardFocused)
        .focusEffectDisabled()
        .onKeyPress(phases: .down) { handleKey($0.key) }
        .onAppear { keyboardFocused = true }
        .onChange(of: phaseKey) { keyboardFocused = true }
        .onChange(of: confirmQuit) { _, shown in if !shown { keyboardFocused = true } }
        .onChange(of: vm.showVoiceHint) { _, shown in if !shown { keyboardFocused = true } }
        .confirmationDialog("End session?", isPresented: $confirmQuit, titleVisibility: .visible) {
            Button("End session", role: .destructive) { vm.quit() }
            Button("Keep going", role: .cancel) { vm.resume() }
        } message: {
            Text("You'll see a summary of the cards answered so far.")
        }
        .alert("No Korean voice installed", isPresented: $vm.showVoiceHint) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("To hear pronunciations, download a Korean voice in Settings → Accessibility → Spoken Content → Voices → Korean.")
        }
    }

    private var phaseKey: Int {
        switch vm.state {
        case let .prompting(p): p.presentationID * 4
        case let .revealed(p, _): p.presentationID * 4 + 1
        case let .paused(p, _): p.presentationID * 4 + 2
        default: -1
        }
    }

    private var topBar: some View {
        VStack(spacing: 6) {
            HStack {
                Button { vm.pause(); confirmQuit = true } label: {
                    Image(systemName: "xmark").font(.title3.weight(.semibold)).frame(width: 44, height: 44)
                }
                .accessibilityLabel("End session")
                .accessibilityIdentifier("closeButton")
                Spacer()
                progressLabel
                Spacer()
                Button { vm.pause() } label: {
                    Image(systemName: "pause.fill").font(.title3).frame(width: 44, height: 44)
                }
                .accessibilityLabel("Pause")
                .accessibilityIdentifier("pauseButton")
                .disabled(isPaused)
            }
            if case .minutes = vm.config.length {
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    ProgressView(value: vm.progress).progressViewStyle(.linear)
                }
            } else {
                ProgressView(value: vm.progress).progressViewStyle(.linear)
            }
        }
        .padding(.horizontal)
        .padding(.top, 4)
    }

    @ViewBuilder private var progressLabel: some View {
        if let text = vm.progressText {
            Text(text).font(.headline.monospacedDigit()).accessibilityLabel("Card \(text)")
        } else {
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                Text(Fmt.clock(vm.remainingSeconds ?? 0)).font(.headline.monospacedDigit())
                    .accessibilityLabel("Time remaining")
            }
        }
    }

    private var isPaused: Bool {
        if case .paused = vm.state { return true }
        return false
    }

    // MARK: States

    private func promptState(_ p: PresentedCard) -> some View {
        layout {
            VStack(spacing: 16) {
                if p.isRetry { retryBadge }
                CardPromptView(card: p.card)
                if env.settings.showTimer {
                    TimelineView(.periodic(from: .now, by: 0.1)) { _ in
                        Text(String(format: "%.1f s", vm.promptElapsedSeconds ?? 0))
                            .font(.title3.monospacedDigit()).foregroundStyle(.secondary)
                    }
                }
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } controls: {
            BigButton(title: "OK", systemImage: "checkmark") { vm.ok() }
                .accessibilityIdentifier("okButton")
        }
        .contentShape(Rectangle())
        .onTapGesture { if env.settings.tapAnywhereForOK { vm.ok() } }
        .task(id: p.presentationID) { vm.promptDidAppear() }
    }

    private func revealState(_ p: PresentedCard, responseMs: Int) -> some View {
        layout {
            ScrollView {
                VStack(spacing: 16) {
                    if p.isRetry { retryBadge }
                    CardAnswerView(card: p.card, maxFret: vm.maxFret)
                    Text(Fmt.seconds(responseMs))
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(Palette.responseColor(ms: responseMs, prior: p.priorEwmaMs))
                        .accessibilityLabel("Response time \(Fmt.seconds(responseMs))")
                }
                .padding()
                .frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize)
            .offset(x: dragOffset)
            .gesture(swipeToGrade)
        } controls: {
            HStack(spacing: 12) {
                BigButton(title: "Wrong", systemImage: "xmark", tint: Palette.wrong) { vm.grade(correct: false) }
                    .accessibilityIdentifier("wrongButton")
                BigButton(title: "Correct", systemImage: "checkmark", tint: Palette.correct) { vm.grade(correct: true) }
                    .accessibilityIdentifier("correctButton")
            }
            // Not `.disabled`: the bordered-prominent grey would flash on every card.
            .opacity(gradeEnabled ? 1 : 0.55)
            .allowsHitTesting(gradeEnabled)
            .animation(reduceMotion ? nil : .easeIn(duration: 0.15), value: gradeEnabled)
        }
        .task(id: phaseKey) {
            gradeEnabled = false
            let remaining = vm.gradeLockoutRemaining
            if remaining > .zero { try? await Task.sleep(for: remaining) }
            if !Task.isCancelled { gradeEnabled = true }
        }
    }

    private func pausedOverlay(_ p: PresentedCard) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "pause.circle.fill").font(.system(size: 64)).foregroundStyle(.secondary)
            Text("Paused").font(.title.weight(.semibold))
            Text("Tap to resume").foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onTapGesture { vm.resume() }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("resumeButton")
    }

    private var retryBadge: some View {
        Label("Retry", systemImage: "arrow.uturn.left")
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(.orange.opacity(0.2), in: Capsule())
    }

    /// Portrait: content above controls. Landscape (compact height): side by side.
    @ViewBuilder
    private func layout(@ViewBuilder content: () -> some View, @ViewBuilder controls: () -> some View) -> some View {
        if verticalSizeClass == .compact {
            HStack(spacing: 16) {
                content()
                controls().frame(maxWidth: 320)
            }
            .padding()
        } else {
            VStack(spacing: 16) {
                content()
                controls()
            }
            .padding()
        }
    }

    private var swipeToGrade: some Gesture {
        DragGesture(minimumDistance: 24)
            .onChanged { dragOffset = $0.translation.width * 0.4 }
            .onEnded { value in
                let dx = value.translation.width
                dragOffset = 0
                if dx > 100 { vm.grade(correct: true) } else if dx < -100 { vm.grade(correct: false) }
            }
    }

    // MARK: Keyboard / pedal

    private func handleKey(_ key: KeyEquivalent) -> KeyPress.Result {
        switch vm.state {
        case .prompting:
            switch key {
            case .space, .return, .rightArrow, .downArrow, .pageDown: vm.ok()
            case .escape: vm.pause()
            default: return .ignored
            }
        case .revealed:
            switch key {
            case .rightArrow, .pageDown, .return: return vm.grade(correct: true) ? .handled : .ignored
            case .leftArrow, .pageUp, .delete: return vm.grade(correct: false) ? .handled : .ignored
            case .escape: vm.pause()
            default: return .ignored
            }
        case .paused:
            switch key {
            case .space, .return, .escape: vm.resume()
            default: return .ignored
            }
        default:
            return .ignored
        }
        return .handled
    }
}

#Preview {
    SessionView(deck: FretboardNotesDeck(), config: .default(for: FretboardNotesDeck()))
        .environment(AppEnvironment.preview())
}
