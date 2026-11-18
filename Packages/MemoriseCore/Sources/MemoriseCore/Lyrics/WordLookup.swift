import Foundation

/// A deck entry found for a lyric token.
public struct WordHit: Hashable, Sendable {
    public let entry: VocabEntry
    public let deckTitle: String
    /// The form of the token that matched (`너` for `너를`). The dictionary form is `entry.hangul`.
    public let matchedForm: String

    public init(entry: VocabEntry, deckTitle: String, matchedForm: String) {
        self.entry = entry
        self.deckTitle = deckTitle
        self.matchedForm = matchedForm
    }
}

/// Looks lyric tokens up in every Korean vocab deck, bundled and user (PLAN_M6 §4.6).
/// Build once per catalog and reuse; it indexes every entry.
public struct WordLookup: Sendable {
    private struct Owned: Sendable {
        let entry: VocabEntry
        let deckTitle: String
    }

    private let exact: [String: Owned]
    private let normalisedIndex: [String: Owned]
    private let byID: [String: Owned]
    /// Matcher over every multi-word entry, for `LyricsTokenizer.tokens(for:phrases:)`.
    public let phrases: PhraseMatcher

    public init(catalog: DeckCatalog) {
        self.init(decks: catalog.vocabDecks)
    }

    /// Ties go to `headwordOwnershipOrder` (R7-F7) first, then other bundled decks, then user decks.
    public init(decks: [VocabDeck]) {
        let order = Dictionary(
            DeckCatalog.headwordOwnershipOrder.enumerated().map { ($1, $0) }, uniquingKeysWith: { a, _ in a })
        func rank(_ d: VocabDeck) -> Int {
            if UserDecks.isUserDeckID(d.id) { return Int.max }
            return order[d.id.raw] ?? DeckCatalog.headwordOwnershipOrder.count
        }
        let ranked = decks.enumerated()
            .filter { $0.element.subject == .korean }
            .sorted { (rank($0.element), $0.offset) < (rank($1.element), $1.offset) }
            .map(\.element)

        var exact: [String: Owned] = [:]
        var normalisedIndex: [String: Owned] = [:]
        var byID: [String: Owned] = [:]
        var ordered: [VocabEntry] = []
        for deck in ranked {
            for e in deck.entries {
                let owned = Owned(entry: e, deckTitle: deck.title)
                let nfc = e.hangul.precomposedStringWithCanonicalMapping
                if exact[nfc] == nil { exact[nfc] = owned }
                let norm = PhraseMatcher.normalised(e.hangul)
                if !norm.isEmpty, normalisedIndex[norm] == nil { normalisedIndex[norm] = owned }
                byID[e.id] = owned
                ordered.append(e)
            }
        }
        self.exact = exact
        self.normalisedIndex = normalisedIndex
        self.byID = byID
        phrases = PhraseMatcher(entries: ordered)
    }

    /// First hit of: exact `hangul`, particle-stripped form, trailing `?!.~`-normalised form.
    public func lookup(_ text: String) -> WordHit? {
        let nfc = text.precomposedStringWithCanonicalMapping
        if let o = exact[nfc] { return hit(o, nfc) }
        let stripped = ScreenshotWords.stripParticle(nfc)
        if stripped != nfc, let o = exact[stripped] { return hit(o, stripped) }
        let norm = PhraseMatcher.normalised(nfc)
        if let o = normalisedIndex[norm] { return hit(o, norm) }
        return nil
    }

    /// Hit for a `.word` (by text) or a `.phrase` (by entry id). `.plain` never hits.
    public func lookup(_ token: LyricToken) -> WordHit? {
        switch token {
        case let .word(text, _): lookup(text)
        case let .phrase(text, entryID, _): byID[entryID].map { hit($0, text) }
        case .plain: nil
        }
    }

    /// Convenience that builds the index per call; prefer an instance for more than one lookup.
    public static func lookup(_ token: LyricToken, in catalog: DeckCatalog) -> WordHit? {
        WordLookup(catalog: catalog).lookup(token)
    }

    private func hit(_ o: Owned, _ form: String) -> WordHit {
        WordHit(entry: o.entry, deckTitle: o.deckTitle, matchedForm: form)
    }
}
