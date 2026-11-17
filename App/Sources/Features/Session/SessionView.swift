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
    /// Last grade for the edge-glow feedback (`true` = correct).
    @State private var flash: Bool?
    @State private var flashToken = 0

    var body: some View {
        Group {
            if case let .finished(summary) = vm.state {
                NavigationStack {
                    SummaryView(summary: summary, deck: vm.deck, saveFailures: vm.saveFailures, celebrate: true)
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
            vm.stopMic()
            env.releaseAudio()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { vm.pause() } else if !vm.usesTextField { keyboardFocused = true }
        }
    }

    // MARK: Running session

    private var subjectColors: [Color] { vm.deck.subject.colors }

    private var running: some View {
        VStack(spacing: 0) {
            topBar
            ZStack {
                // One branch for "revealed" and "paused under the snippet sheet" so the reveal keeps its scroll position.
                if let shown = shownReveal {
                    revealState(shown.card, responseMs: shown.ms)
                        .transition(.asymmetric(
                            insertion: reduceMotion ? .opacity : .modifier(active: FlipIn(progress: 0), identity: FlipIn(progress: 1)),
                            removal: .identity
                        ))
                } else {
                    switch vm.state {
                    case let .prompting(p):
                        promptState(p)
                            // Instant: the response timer starts on appear, so no entry animation.
                            .transition(.identity)
                    case let .paused(p, _):
                        pausedOverlay(p)
                            .transition(.opacity.combined(with: .scale(scale: 0.94)))
                    default:
                        ProgressView()
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(reduceMotion ? .easeOut(duration: 0.12) : .spring(response: 0.32, dampingFraction: 0.78), value: phaseKey)
            typedField
        }
        .background { AuroraBackground(colors: subjectColors, intensity: 0.85, animated: false) }
        .overlay { gradeFlashOverlay }
        .focusable()
        .focused($keyboardFocused)
        .focusEffectDisabled()
        .onKeyPress(phases: .down) { handleKey($0.key) }
        .onAppear { if !vm.usesTextField { keyboardFocused = true } }
        #if DEBUG && targetEnvironment(simulator)
        // `-uiReveal YES` reveals the first card (UI screenshots).
        .task {
            guard UserDefaults.standard.bool(forKey: "uiReveal") else { return }
            try? await Task.sleep(for: .seconds(1))
            vm.ok()
        }
        #endif
        .onChange(of: phaseKey) { if !vm.usesTextField { keyboardFocused = true }; dragOffset = 0 }
        .onChange(of: confirmQuit) { _, shown in if !shown, !vm.usesTextField { keyboardFocused = true } }
        .onChange(of: vm.showVoiceHint) { _, shown in if !shown, !vm.usesTextField { keyboardFocused = true } }
        .task(id: flashToken) {
            guard flash != nil else { return }
            try? await Task.sleep(for: .milliseconds(160))
            withAnimation(.easeOut(duration: 0.35)) { flash = nil }
        }
        .confirmationDialog("End session?", isPresented: $confirmQuit, titleVisibility: .visible) {
            Button("End session", role: .destructive) { vm.quit() }
            Button("Keep going", role: .cancel) { vm.resume() }
        } message: {
            Text("You'll see a summary of the cards answered so far.")
        }
        .sheet(item: $vm.snippetTarget, onDismiss: { vm.snippetSheetDismissed() }) { target in
            SnippetEditorSheet(entry: target.entry)
        }
        .alert("No Korean voice installed", isPresented: $vm.showVoiceHint) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("To hear pronunciations, download a Korean voice in Settings → Accessibility → Spoken Content → Voices → Korean.")
        }
    }

    /// Brief coloured edge glow after each grade.
    @ViewBuilder private var gradeFlashOverlay: some View {
        if let flash {
            Rectangle()
                .strokeBorder(flash ? Theme.correctGradient : Theme.wrongGradient, lineWidth: 10)
                .blur(radius: 14)
                .ignoresSafeArea()
                .allowsHitTesting(false)
                .transition(.opacity)
                .accessibilityHidden(true)
        }
    }

    /// Grades and, if accepted, fires the visual feedback.
    @discardableResult
    private func grade(_ correct: Bool) -> Bool {
        let accepted = vm.grade(correct: correct)
        if accepted {
            withAnimation(.easeOut(duration: 0.08)) { flash = correct }
            flashToken += 1
        }
        return accepted
    }

    /// Next on a typed/choice reveal: stores the checked verdict (or the override).
    @discardableResult
    private func gradeAuto() -> Bool {
        guard let auto = vm.autoAnswer else { return false }
        return grade(auto.correct)
    }

    /// Persistent typed-answer field (kept mounted across cards so the keyboard stays up).
    @ViewBuilder private var typedField: some View {
        if vm.usesTextField, let spec = vm.typedSpec, let p = vm.state.presented, !isPaused {
            let prompting: Bool = if case .prompting = vm.state { true } else { false }
            TypedAnswerField(
                kind: spec.kind, resetID: p.presentationID, isEditable: prompting, colors: subjectColors,
                onSubmit: { vm.submitTyped($0) },
                onNext: { gradeAuto() }
            )
            .padding(.horizontal)
            .padding(.bottom, 8)
        }
    }

    private var phaseKey: Int {
        switch vm.state {
        case let .prompting(p): p.presentationID * 4
        case let .revealed(p, _): p.presentationID * 4 + 1
        case let .paused(p, ms): p.presentationID * 4 + (ms != nil && vm.snippetTarget != nil ? 1 : 2)
        default: -1
        }
    }

    private var topBar: some View {
        VStack(spacing: 10) {
            HStack {
                CircleIconButton(systemImage: "xmark") { vm.pause(); confirmQuit = true }
                    .accessibilityLabel("End session")
                    .accessibilityIdentifier("closeButton")
                Spacer()
                progressLabel
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(.thinMaterial, in: Capsule())
                Spacer()
                CircleIconButton(systemImage: "pause.fill") { vm.pause() }
                    .accessibilityLabel("Pause")
                    .accessibilityIdentifier("pauseButton")
                    .disabled(isPaused)
                    .opacity(isPaused ? 0.4 : 1)
            }
            if case .minutes = vm.config.length {
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    GradientProgressBar(value: vm.progress, colors: subjectColors)
                }
            } else {
                GradientProgressBar(value: vm.progress, colors: subjectColors)
            }
        }
        .padding(.horizontal)
        .padding(.top, 4)
    }

    @ViewBuilder private var progressLabel: some View {
        if let text = vm.progressText {
            Text(text)
                .font(.system(.headline, design: .rounded, weight: .bold).monospacedDigit())
                .contentTransition(.numericText())
                .animation(Theme.spring, value: text)
                .accessibilityLabel("Card \(text)")
        } else {
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                Label(Fmt.clock(vm.remainingSeconds ?? 0), systemImage: "timer")
                    .font(.system(.headline, design: .rounded, weight: .bold).monospacedDigit())
                    .accessibilityLabel("Time remaining")
            }
        }
    }

    /// The reveal to show: while revealed, or while paused for the snippet sheet.
    private var shownReveal: (card: PresentedCard, ms: Int)? {
        switch vm.state {
        case let .revealed(p, ms): (p, ms)
        case let .paused(p, ms?) where vm.snippetTarget != nil: (p, ms)
        default: nil
        }
    }

    private var isPaused: Bool {
        if case .paused = vm.state { return true }
        return false
    }

    // MARK: States

    /// The flashcard surface.
    private func cardSurface(stacked: Bool = true, @ViewBuilder _ content: () -> some View) -> some View {
        content()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(alignment: .bottomTrailing) {
                // Faint subject watermark for depth.
                vm.deck.subject.glyph
                    .font(.system(size: 150))
                    .foregroundStyle(subjectColors[0].opacity(0.06))
                    .rotationEffect(.degrees(-14))
                    .offset(x: 30, y: 30)
                    .accessibilityHidden(true)
            }
            .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
            .glassCard(radius: 32, tint: subjectColors[0])
            .background(alignment: .bottom) { if stacked { deckStack } }
    }

    /// Two cards peeking out below the current one, so it reads as a deck.
    private var deckStack: some View {
        ZStack(alignment: .bottom) {
            ForEach([2, 1], id: \.self) { i in
                RoundedRectangle(cornerRadius: 32, style: .continuous)
                    .fill(.regularMaterial)
                    .overlay(RoundedRectangle(cornerRadius: 32, style: .continuous).fill(subjectColors[i % subjectColors.count].opacity(0.18)))
                    .overlay(RoundedRectangle(cornerRadius: 32, style: .continuous).strokeBorder(.white.opacity(0.35), lineWidth: 1))
                    .shadow(color: subjectColors[0].opacity(0.12), radius: 6, y: 3)
                    .scaleEffect(x: 1 - 0.06 * Double(i), y: 1, anchor: .bottom)
                    .offset(y: 9 * Double(i))
                    .opacity(1 - 0.25 * Double(i))
            }
        }
        .accessibilityHidden(true)
    }

    private func promptState(_ p: PresentedCard) -> some View {
        layout {
            cardSurface {
                VStack(spacing: 16) {
                    if p.isRetry { retryBadge }
                    if let reason = vm.micFallbackReason { micFallbackNote(reason) }
                    CardPromptView(card: p.card, ctx: vm.context(presentationID: p.presentationID))
                    if let mic = vm.mic { MicListeningChip(mic: mic) }
                    if env.settings.showTimer {
                        TimelineView(.periodic(from: .now, by: 0.1)) { _ in
                            Text(String(format: "%.1f s", vm.promptElapsedSeconds ?? 0))
                                .font(.system(.title3, design: .rounded, weight: .semibold).monospacedDigit())
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 12).padding(.vertical, 4)
                                .background(.primary.opacity(0.06), in: Capsule())
                        }
                    }
                }
                .padding(24)
            }
        } controls: {
            switch vm.activeMode {
            case .choice:
                ChoiceGrid(choices: vm.choices ?? [], colors: subjectColors) { vm.choose($0) }
            case .typed:
                Button("Don't know") { vm.giveUp() }
                    .font(.headline)
                    .foregroundStyle(.secondary)
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("dontKnowButton")
            case .touch, .microphone:
                BigButton(title: "Reveal", systemImage: "eye.fill", colors: subjectColors) { vm.ok() }
                    .accessibilityIdentifier("okButton")
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { if env.settings.tapAnywhereForOK { vm.ok() } }
        // Ear-training prompts start the timer themselves (when the second note sounds).
        .task(id: p.presentationID) { if !vm.managesPromptTiming(p.card) { vm.promptDidAppear() } }
    }

    private func revealState(_ p: PresentedCard, responseMs: Int) -> some View {
        let swipe = max(-1, min(1, dragOffset / 140))
        return layout {
            cardSurface(stacked: false) {
                GeometryReader { geo in
                ScrollView {
                    VStack(spacing: 16) {
                        if p.isRetry { retryBadge }
                        if let auto = vm.autoAnswer { VerdictBanner(answer: auto) }
                        CardAnswerView(card: p.card, ctx: vm.context(presentationID: p.presentationID))
                        let color = Palette.responseColor(ms: responseMs, prior: p.priorEwmaMs)
                        Label(Fmt.seconds(responseMs), systemImage: "stopwatch.fill")
                            .font(.system(.headline, design: .rounded, weight: .bold).monospacedDigit())
                            .foregroundStyle(color)
                            .padding(.horizontal, 14).padding(.vertical, 6)
                            .background(color.opacity(0.14), in: Capsule())
                            .accessibilityLabel("Response time \(Fmt.seconds(responseMs))")
                    }
                    .padding(24)
                    .frame(maxWidth: .infinity)
                    // Short answers sit centred; long ones scroll from the top.
                    .frame(minHeight: geo.size.height)
                }
                .scrollBounceBehavior(.basedOnSize)
                }
            }
            .overlay { swipeTint(swipe) }
            .offset(x: dragOffset)
            .rotationEffect(.degrees(reduceMotion ? 0 : Double(swipe) * 8), anchor: .bottom)
            .gesture(swipeToGrade, isEnabled: vm.autoAnswer == nil)
            // The deck stays put while the top card is swiped.
            .background(alignment: .bottom) { deckStack }
        } controls: {
            if let auto = vm.autoAnswer {
                autoControls(auto)
                    .opacity(gradeEnabled ? 1 : 0.55)
                    .allowsHitTesting(gradeEnabled)
            } else {
                selfGradeControls(swipe)
            }
        }
        .task(id: phaseKey) {
            gradeEnabled = false
            let remaining = vm.gradeLockoutRemaining
            if remaining > .zero { try? await Task.sleep(for: remaining) }
            guard !Task.isCancelled else { return }
            gradeEnabled = true
            // Exactly correct typed/choice answers move on by themselves.
            guard env.settings.autoAdvanceOnCorrect, let auto = vm.autoAnswer, auto.verdict == .exact, auto.override == nil else { return }
            try? await Task.sleep(for: .milliseconds(800))
            if !Task.isCancelled, vm.autoAnswer?.override == nil { gradeAuto() }
        }
    }

    /// Next + "I was right / wrong" for checked answers.
    private func autoControls(_ auto: AutoAnswer) -> some View {
        VStack(spacing: 10) {
            if auto.input != nil {
                Button(auto.correct ? "I was wrong" : "I was right") {
                    vm.overrideAutoAnswer(correct: !auto.correct)
                }
                .font(.subheadline.weight(.semibold))
                .frame(minHeight: 44)
                .accessibilityIdentifier(auto.correct ? "overrideWrongButton" : "overrideRightButton")
            }
            BigButton(title: "Next", systemImage: "arrow.right", colors: auto.correct ? [Theme.mint, Theme.teal] : [Theme.rose, Theme.amber]) {
                gradeAuto()
            }
            .accessibilityIdentifier("nextButton")
        }
    }

    private func selfGradeControls(_ swipe: CGFloat) -> some View {
            HStack(spacing: 12) {
                BigButton(title: "Wrong", systemImage: "xmark", colors: [Theme.rose, Theme.amber]) { grade(false) }
                    .accessibilityIdentifier("wrongButton")
                    .scaleEffect(swipe < 0 ? 1 + abs(swipe) * 0.06 : 1)
                BigButton(title: "Correct", systemImage: "checkmark", colors: [Theme.mint, Theme.teal]) { grade(true) }
                    .accessibilityIdentifier("correctButton")
                    .scaleEffect(swipe > 0 ? 1 + swipe * 0.06 : 1)
            }
            // Not `.disabled`: the disabled grey would flash on every card.
            .opacity(gradeEnabled ? 1 : 0.55)
            .allowsHitTesting(gradeEnabled)
            .animation(reduceMotion ? nil : .easeIn(duration: 0.15), value: gradeEnabled)
    }

    /// Green/red wash + icon while the card is dragged.
    @ViewBuilder private func swipeTint(_ swipe: CGFloat) -> some View {
        if swipe != 0 {
            let correct = swipe > 0
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .fill((correct ? Theme.correctGradient : Theme.wrongGradient).opacity(abs(swipe) * 0.35))
                .overlay(alignment: correct ? .topLeading : .topTrailing) {
                    Image(systemName: correct ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .font(.system(size: 48, weight: .bold))
                        .foregroundStyle(.white)
                        .shadow(radius: 6)
                        .scaleEffect(0.6 + abs(swipe) * 0.5)
                        .opacity(Double(abs(swipe)))
                        .padding(24)
                }
                .allowsHitTesting(false)
        }
    }

    private func pausedOverlay(_ p: PresentedCard) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "pause.circle.fill")
                .font(.system(size: 72))
                .foregroundStyle(LinearGradient(colors: subjectColors, startPoint: .topLeading, endPoint: .bottomTrailing))
                .symbolEffect(.pulse, options: .repeating, isActive: !reduceMotion)
            Text("Paused").font(.system(.largeTitle, design: .rounded, weight: .bold))
            Text("Tap anywhere to resume").foregroundStyle(.secondary)
        }
        .padding(40)
        .glassCard(radius: 32, tint: subjectColors[0])
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onTapGesture { vm.resume() }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("resumeButton")
    }

    private func micFallbackNote(_ text: String) -> some View {
        Label(text, systemImage: "mic.slash.fill")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12).padding(.vertical, 5)
            .background(.primary.opacity(0.06), in: Capsule())
    }

    private var retryBadge: some View {
        Label("Retry", systemImage: "arrow.uturn.left")
            .font(.caption.weight(.bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 12).padding(.vertical, 5)
            .background(LinearGradient(colors: [Theme.amber, .orange], startPoint: .leading, endPoint: .trailing), in: Capsule())
            .shadow(color: .orange.opacity(0.4), radius: 6, y: 3)
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
            VStack(spacing: 20) {
                content()
                controls()
            }
            .padding()
        }
    }

    private var swipeToGrade: some Gesture {
        DragGesture(minimumDistance: 24)
            .onChanged { dragOffset = $0.translation.width }
            .onEnded { value in
                let dx = value.translation.width + (value.predictedEndTranslation.width - value.translation.width) * 0.3
                if dx > 120 { grade(true) } else if dx < -120 { grade(false) }
                withAnimation(Theme.spring) { dragOffset = 0 }
            }
    }

    // MARK: Keyboard / pedal

    private func handleKey(_ key: KeyEquivalent) -> KeyPress.Result {
        switch vm.state {
        case .prompting where vm.activeMode == .typed || vm.activeMode == .choice:
            // The text field / option shortcuts own the keyboard; the pedal can't reveal.
            if key == .escape { vm.pause(); return .handled }
            return .ignored
        case .revealed where vm.autoAnswer != nil:
            switch key {
            case .rightArrow, .pageDown, .return, .space: return gradeAuto() ? .handled : .ignored
            case .escape: vm.pause()
            default: return .ignored
            }
        case .prompting:
            switch key {
            case .space, .return, .rightArrow, .downArrow, .pageDown: vm.ok()
            case .escape: vm.pause()
            default: return .ignored
            }
        case .revealed:
            switch key {
            case .rightArrow, .pageDown, .return: return grade(true) ? .handled : .ignored
            case .leftArrow, .pageUp, .delete: return grade(false) ? .handled : .ignored
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

/// 3D flip-in used when the answer is revealed.
private struct FlipIn: ViewModifier {
    let progress: Double

    func body(content: Content) -> some View {
        content
            .rotation3DEffect(.degrees((1 - progress) * -75), axis: (x: 0, y: 1, z: 0), perspective: 0.5)
            .scaleEffect(0.92 + 0.08 * progress)
            .opacity(min(1, progress * 2))
    }
}

#Preview {
    SessionView(deck: FretboardNotesDeck(), config: .default(for: FretboardNotesDeck()))
        .environment(AppEnvironment.preview())
}

/// "Listening…" chip with a live level meter and a transient "Heard G♯" note.
private struct MicListeningChip: View {
    let mic: MicAnswerController
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "mic.fill")
                .foregroundStyle(Subject.music.gradient)
                .symbolEffect(.pulse, options: .repeating, isActive: mic.isListening && !reduceMotion)
            Text(mic.heardWrong.map { "Heard \($0)" } ?? (mic.isListening ? "Listening…" : "Mic paused"))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(mic.heardWrong == nil ? Color.primary : Theme.rose)
                .contentTransition(.opacity)
            LevelMeter(levelDB: mic.levelDB)
                .frame(width: 60, height: 6)
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .background(.thinMaterial, in: Capsule())
        .animation(.easeOut(duration: 0.15), value: mic.heardWrong)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("micChip")
    }
}

/// Input level bar (−60…0 dBFS).
private struct LevelMeter: View {
    let levelDB: Double

    var body: some View {
        GeometryReader { geo in
            let v = max(0, min(1, (levelDB + 60) / 60))
            ZStack(alignment: .leading) {
                Capsule().fill(.primary.opacity(0.1))
                Capsule().fill(LinearGradient(colors: [Theme.mint, Theme.amber, Theme.rose], startPoint: .leading, endPoint: .trailing))
                    .frame(width: geo.size.width * v)
            }
        }
        .accessibilityHidden(true)
    }
}

