import Foundation
import MemoriseCore
import Observation
@preconcurrency import Translation

/// What the bubble shows for a word (PLAN_M6 §4.8).
enum GlossState: Equatable {
    /// A deck entry: show its curated meaning, the dictionary form when it differs, and "In: <deck>".
    case deck(VocabEntry, deckTitle: String, matchedForm: String)
    /// On-device Translation (ko→en). Label it "Auto-translated".
    case auto(String)
    /// Not translated yet: show a spinner.
    case pending
    /// No meaning available (language pack missing or declined, or the word couldn't be translated).
    case unavailable
}

/// Word meanings for the lyrics bubble: the user's decks first, then Apple's on-device Translation.
///
/// A `TranslationSession` only exists inside a view's `.translationTask` closure, so the reader calls
/// `prepare(document:track:)` when the lyrics load and `runBatch(session:track:)` from that closure.
@MainActor @Observable
final class GlossService {
    private var lookup: WordLookup
    @ObservationIgnored private let cache: LyricsCacheStore
    /// Machine glosses by track id, then by NFC word text.
    private var glosses: [String: [String: String]] = [:]
    /// Words that couldn't be translated, by track id.
    private var failed: [String: Set<String>] = [:]
    /// The user declined (or can't get) the Korean language pack: don't prompt again this launch.
    /// Reset only by `retryFailed` (the reader's pull to refresh).
    @ObservationIgnored private var translationDeclined = false
    /// Unique words of each prepared song that no deck knows, in first-seen order.
    @ObservationIgnored private var wanted: [String: [String]] = [:]

    init(catalog: DeckCatalog, cache: LyricsCacheStore) {
        lookup = WordLookup(catalog: catalog)
        self.cache = cache
    }

    /// Call when the catalog is rebuilt (a word was added to a user deck), so new hits show immediately.
    func catalogDidChange(_ catalog: DeckCatalog) {
        lookup = WordLookup(catalog: catalog)
    }

    /// The phrase matcher and lookup the reader tokenises with.
    var wordLookup: WordLookup { lookup }

    // MARK: Meanings

    func meaning(for token: LyricToken, track: String) -> GlossState {
        let text: String
        switch token {
        case .plain:
            return .unavailable
        case .phrase:
            guard let hit = lookup.lookup(token) else { return .unavailable }
            return .deck(hit.entry, deckTitle: hit.deckTitle, matchedForm: hit.matchedForm)
        case let .word(t, _):
            if let hit = lookup.lookup(token) { return .deck(hit.entry, deckTitle: hit.deckTitle, matchedForm: hit.matchedForm) }
            text = t
        }
        let key = Self.key(text)
        if let gloss = glosses[track]?[key] { return .auto(gloss) }
        if failed[track]?.contains(key) == true { return .unavailable }
        return .pending
    }

    /// Unique word texts of the prepared song that still need a translation.
    func pendingTexts(track: String) -> [String] {
        let have = glosses[track] ?? [:]
        let bad = failed[track] ?? []
        return (wanted[track] ?? []).filter { have[Self.key($0)] == nil && !bad.contains(Self.key($0)) }
    }

    /// Records translations (main actor) and persists them in the lyrics cache.
    func store(_ results: [String: String], track: String) {
        var clean: [String: String] = [:]
        for (text, gloss) in results {
            let g = gloss.trimmingCharacters(in: .whitespacesAndNewlines)
            let key = Self.key(text)
            // A translation that just echoes the Korean word is no meaning.
            if !g.isEmpty, g != text { clean[key] = g }
        }
        guard !clean.isEmpty else { return }
        glosses[track, default: [:]].merge(clean) { _, new in new }
        let cache = cache
        Task { await cache.mergeGlosses(clean, for: track) }
    }

    // MARK: Song set-up

    /// Collects the song's words that need translating and loads glosses cached on an earlier visit.
    func prepare(document: LyricsDocument, track: String) async {
        var seen = Set<String>()
        var words: [String] = []
        for line in document.korean {
            for token in LyricsTokenizer.tokens(for: line, phrases: lookup.phrases) {
                guard case let .word(text, _) = token, lookup.lookup(token) == nil, seen.insert(Self.key(text)).inserted
                else { continue }
                words.append(text)
            }
        }
        wanted[track] = words
        failed[track] = []
        if let cached = await cache.load(track)?.glosses, !cached.isEmpty {
            glosses[track, default: [:]].merge(cached) { mine, _ in mine }
        }
    }

    /// Forgets words marked as failed, so the reader can try the batch again.
    func retryFailed(track: String) {
        failed[track] = []
        translationDeclined = false
    }

    /// Empties every in-memory gloss (Settings → Clear lyrics cache).
    func clearAll() {
        glosses = [:]
        failed = [:]
        wanted = [:]
        translationDeclined = false
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

    /// Translates every pending word of `track` with the session from `.translationTask`, filling the bubbles as
    /// results arrive. Words that can't be translated (pack declined, unsupported, error) become `.unavailable`.
    func runBatch(session: TranslationSession, track: String) async {
        let texts = pendingTexts(track: track)
        guard !texts.isEmpty else { return }
        guard !translationDeclined else { markFailed(texts, track: track); return }
        guard await Self.availability() != .unavailable else {
            translationDeclined = true
            markFailed(texts, track: track)
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
            markFailed(texts, track: track)
            return
        }
        do {
            let requests = texts.map { TranslationSession.Request(sourceText: $0, clientIdentifier: $0) }
            for try await response in session.translate(batch: requests) {
                if let id = response.clientIdentifier { store([id: response.targetText], track: track) }
            }
        } catch is CancellationError {
            return
        } catch {
            AppEnvironment.log.error("Translation failed: \(error.localizedDescription, privacy: .public)")
        }
        // Whatever is still missing won't come: show "Meaning unavailable" instead of a spinner.
        markFailed(pendingTexts(track: track), track: track)
    }

    private func markFailed(_ texts: [String], track: String) {
        failed[track, default: []].formUnion(texts.map(Self.key))
    }

    private static func key(_ text: String) -> String { text.precomposedStringWithCanonicalMapping }
}
