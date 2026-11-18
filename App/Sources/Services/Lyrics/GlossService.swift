import Foundation
import MemoriseCore
import Observation
@preconcurrency import Translation

/// What the bubble shows for a word (PLAN_M6 §4.8, PLAN_R10 LA2).
enum GlossState: Equatable {
    /// A deck entry: show its curated meaning, the dictionary form when it differs, and "In: <deck>".
    case deck(VocabEntry, deckTitle: String, matchedForm: String)
    /// On-device Translation (ko→en). Label it "Auto-translated".
    case auto(String)
    /// Not translated yet: show a spinner.
    case pending
    /// The language pack is missing or was declined.
    case needsLanguagePack
    /// Translated, but no usable single-word meaning; the bubble leans on the line.
    case noWordMeaning
}

/// What the bubble and the English page show for a whole line (PLAN_R10 P-4, O-2).
enum LineGloss: Equatable {
    case genius(String)
    case auto(String)
    case pending
    case needsLanguagePack
    case unavailable
}

/// Word and line meanings for the lyrics reader: the user's decks first, then Apple's on-device Translation.
///
/// A `TranslationSession` only exists inside a view's `.translationTask` closure, so the reader calls
/// `prepare(document:track:needsLines:)` when the lyrics load and `runBatch(session:track:)` from that closure.
///
/// Gloss storage is `@ObservationIgnored`: views observe the single `revision` counter, which is bumped once per
/// applied chunk of results, so a batch of 150 words doesn't re-render every token 150 times.
@MainActor @Observable
final class GlossService {
    /// Bumped once per applied chunk of results. `meaning` and `lineMeaning` read it, so callers that use them
    /// in a view body re-render when glosses change. Token views must not read it.
    private(set) var revision = 0

    @ObservationIgnored private var lookup: WordLookup
    @ObservationIgnored private let cache: LyricsCacheStore
    @ObservationIgnored private let now: () -> ContinuousClock.Instant
    /// Machine glosses by track id, then by NFC word text.
    @ObservationIgnored private var glosses: [String: [String: String]] = [:]
    /// Machine translations of lines by track id, then by `GlossText.lineKey`.
    @ObservationIgnored private var lineGlosses: [String: [String: String]] = [:]
    @ObservationIgnored private var failedWords: [String: Set<String>] = [:]
    @ObservationIgnored private var failedLines: [String: Set<String>] = [:]
    /// The user declined (or can't get) the Korean language pack: don't prompt again this launch.
    /// Reset only by `retryFailed` (the reader's pull to refresh).
    @ObservationIgnored private var translationDeclined = false
    /// Unique words of each prepared song that no deck knows, in first-seen order.
    @ObservationIgnored private var wantedWords: [String: [String]] = [:]
    /// Unique Hangul line texts of each prepared song, in first-seen order. Empty unless lines were requested.
    @ObservationIgnored private var wantedLines: [String: [String]] = [:]
    /// Tracks prepared with `needsLines == true`.
    @ObservationIgnored private var linesRequested: Set<String> = []

    /// Results are applied after this many, or after this long, whichever comes first.
    private static let applyEvery = 40
    private static let applyInterval: Duration = .milliseconds(250)

    init(catalog: DeckCatalog, cache: LyricsCacheStore, now: @escaping () -> ContinuousClock.Instant = { .now }) {
        lookup = WordLookup(catalog: catalog)
        self.cache = cache
        self.now = now
    }

    /// Call when the catalog is rebuilt (a word was added to a user deck), so new hits show immediately.
    func catalogDidChange(_ catalog: DeckCatalog) {
        lookup = WordLookup(catalog: catalog)
    }

    /// The phrase matcher and lookup the reader tokenises with.
    var wordLookup: WordLookup { lookup }

    /// True when the language pack is missing or was declined (this launch).
    var languagePackMissing: Bool {
        _ = revision
        return translationDeclined
    }

    // MARK: Meanings

    func meaning(for token: LyricToken, track: String) -> GlossState {
        _ = revision
        let text: String
        switch token {
        case .plain:
            return .noWordMeaning
        case .phrase:
            guard let hit = lookup.lookup(token) else { return .noWordMeaning }
            return .deck(hit.entry, deckTitle: hit.deckTitle, matchedForm: hit.matchedForm)
        case let .word(t, _):
            if let hit = lookup.lookup(token) { return .deck(hit.entry, deckTitle: hit.deckTitle, matchedForm: hit.matchedForm) }
            text = t
        }
        let key = Self.key(text)
        if let gloss = glosses[track]?[key] { return .auto(gloss) }
        if failedWords[track]?.contains(key) == true { return translationDeclined ? .needsLanguagePack : .noWordMeaning }
        return .pending
    }

    /// The machine translation of a whole line, or `nil` when the song was prepared without lines.
    func lineMeaning(_ text: String, track: String) -> LineGloss? {
        _ = revision
        guard linesRequested.contains(track) else { return nil }
        let key = GlossText.lineKey(text)
        if let gloss = lineGlosses[track]?[key] { return .auto(gloss) }
        if failedLines[track]?.contains(key) == true { return translationDeclined ? .needsLanguagePack : .unavailable }
        return .pending
    }

    /// Whether any word or line of the prepared song still waits for a translation.
    func hasPending(track: String) -> Bool {
        !pendingWords(track: track).isEmpty || !pendingLines(track: track).isEmpty
    }

    private func pendingWords(track: String) -> [String] {
        let have = glosses[track] ?? [:]
        let bad = failedWords[track] ?? []
        return (wantedWords[track] ?? []).filter { have[Self.key($0)] == nil && !bad.contains(Self.key($0)) }
    }

    private func pendingLines(track: String) -> [String] {
        let have = lineGlosses[track] ?? [:]
        let bad = failedLines[track] ?? []
        return (wantedLines[track] ?? []).filter { have[GlossText.lineKey($0)] == nil && !bad.contains(GlossText.lineKey($0)) }
    }

    // MARK: Song set-up

    /// Collects the song's words (and lines, when `needsLines`) that need translating and loads the glosses cached
    /// on an earlier visit, with one cache read. `needsLines` is false only when the document has Genius English
    /// that lines up with the Korean one to one.
    func prepare(document: LyricsDocument, track: String, needsLines: Bool) async {
        var seen = Set<String>()
        var words: [String] = []
        var lineSeen = Set<String>()
        var lines: [String] = []
        for line in document.korean where !line.isSectionHeader {
            for token in LyricsTokenizer.tokens(for: line, phrases: lookup.phrases) {
                guard case let .word(text, _) = token, GlossText.containsHangul(text), lookup.lookup(token) == nil,
                      seen.insert(Self.key(text)).inserted else { continue }
                words.append(text)
            }
            if needsLines, GlossText.containsHangul(line.text), lineSeen.insert(GlossText.lineKey(line.text)).inserted {
                lines.append(line.text)
            }
        }
        wantedWords[track] = words
        wantedLines[track] = lines
        failedWords[track] = []
        failedLines[track] = []
        if needsLines { linesRequested.insert(track) } else { linesRequested.remove(track) }
        if let file = await cache.load(track) {
            // Glosses cached by an older build may be echoes or Hangul: drop those so they're translated again.
            let usableWords = file.glosses.filter { GlossText.isUsableGloss($0.value, for: $0.key) }
            let usableLines = file.lineGlosses.filter { GlossText.isUsableGloss($0.value, for: $0.key) }
            glosses[track, default: [:]].merge(usableWords) { mine, _ in mine }
            lineGlosses[track, default: [:]].merge(usableLines) { mine, _ in mine }
        }
        revision += 1
    }

    /// Forgets words and lines marked as failed, so the reader can try the batch again.
    func retryFailed(track: String) {
        failedWords[track] = []
        failedLines[track] = []
        translationDeclined = false
        revision += 1
    }

    /// Empties every in-memory gloss (Settings → Clear lyrics cache).
    func clearAll() {
        glosses = [:]
        lineGlosses = [:]
        failedWords = [:]
        failedLines = [:]
        wantedWords = [:]
        wantedLines = [:]
        linesRequested = []
        translationDeclined = false
        revision += 1
    }

    // MARK: Apple Translation

    enum Availability { case installed, needsDownload, unavailable }

    static let source = Locale.Language(identifier: "ko")
    static let target = Locale.Language(identifier: "en")

    static func availability() async -> Availability {
        switch await LanguageAvailability().status(from: source, to: target) {
        case .installed: .installed
        case .supported: .needsDownload
        default: .unavailable
        }
    }

    private enum Kind { case word, line }

    /// Translates the pending words, then the stems of the words that failed, then the pending lines of `track`
    /// with the session from `.translationTask`. Results are applied in chunks, and the cache is written once per
    /// pass. Whatever can't be translated (pack declined, unsupported, error) is marked failed, so no spinner spins
    /// forever.
    func runBatch(session: TranslationSession, track: String) async {
        let words = pendingWords(track: track)
        let lines = pendingLines(track: track)
        guard !words.isEmpty || !lines.isEmpty else { return }
        guard !translationDeclined else { declineAll(words: words, lines: lines, track: track); return }
        guard await Self.availability() != .unavailable else {
            translationDeclined = true
            declineAll(words: words, lines: lines, track: track)
            return
        }
        do {
            // Shows the system download prompt when the Korean pack isn't installed yet.
            try await session.prepareTranslation()
        } catch is CancellationError {
            return
        } catch {
            // Download declined or failed: remember it, so the next song doesn't prompt again.
            translationDeclined = true
            declineAll(words: words, lines: lines, track: track)
            return
        }

        // 1. Words.
        let wordItems = words.map { Item(key: Self.key($0), source: $0) }
        guard await pass(wordItems, kind: .word, session: session, track: track) else { return }

        // 2. Fallback: the stem of every word that is still missing ("사랑을" → "사랑"), stored under the word.
        let missing = pendingWords(track: track)
        let stemItems = missing.compactMap { word in
            GlossText.fallbackForm(word).map { Item(key: Self.key(word), source: $0) }
        }
        if !stemItems.isEmpty {
            guard await pass(stemItems, kind: .word, session: session, track: track) else { return }
        }
        failedWords[track, default: []].formUnion(pendingWords(track: track).map(Self.key))

        // 3. Lines.
        let lineItems = pendingLines(track: track).map { Item(key: GlossText.lineKey($0), source: $0) }
        if !lineItems.isEmpty {
            guard await pass(lineItems, kind: .line, session: session, track: track) else { return }
        }
        failedLines[track, default: []].formUnion(pendingLines(track: track).map(GlossText.lineKey))
        revision += 1
    }

    private struct Item {
        /// Where the gloss is stored. For a stem pass this is the original word.
        let key: String
        /// What is sent to Translation.
        let source: String
    }

    /// One translation pass. Returns false when it was cancelled (what had arrived is applied and written first).
    private func pass(_ items: [Item], kind: Kind, session: TranslationSession, track: String) async -> Bool {
        let sources = Dictionary(items.map { ($0.key, $0.source) }, uniquingKeysWith: { first, _ in first })
        let requests = items.map { TranslationSession.Request(sourceText: $0.source, clientIdentifier: $0.key) }
        var buffer: [String: String] = [:]
        var written: [String: String] = [:]
        var lastApply = now()
        var cancelled = false

        func apply() {
            guard !buffer.isEmpty else { return }
            switch kind {
            case .word: glosses[track, default: [:]].merge(buffer) { _, new in new }
            case .line: lineGlosses[track, default: [:]].merge(buffer) { _, new in new }
            }
            written.merge(buffer) { _, new in new }
            buffer = [:]
            lastApply = now()
            revision += 1
        }

        do {
            for try await response in session.translate(batch: requests) {
                guard let id = response.clientIdentifier, let source = sources[id] else { continue }
                if GlossText.isUsableGloss(response.targetText, for: source) {
                    buffer[id] = response.targetText.trimmingCharacters(in: .whitespacesAndNewlines)
                }
                if buffer.count >= Self.applyEvery || now() - lastApply >= Self.applyInterval { apply() }
            }
        } catch is CancellationError {
            cancelled = true
        } catch {
            AppEnvironment.log.error("Translation failed: \(error.localizedDescription, privacy: .public)")
        }
        apply()
        if !written.isEmpty {
            switch kind {
            case .word: await cache.mergeGlosses(words: written, lines: [:], for: track)
            case .line: await cache.mergeGlosses(words: [:], lines: written, for: track)
            }
        }
        return !cancelled
    }

    private func declineAll(words: [String], lines: [String], track: String) {
        failedWords[track, default: []].formUnion(words.map(Self.key))
        failedLines[track, default: []].formUnion(lines.map(GlossText.lineKey))
        revision += 1
    }

    private static func key(_ text: String) -> String { text.precomposedStringWithCanonicalMapping }
}
