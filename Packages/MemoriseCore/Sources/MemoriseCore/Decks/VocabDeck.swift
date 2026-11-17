/// A vocabulary deck backed by a `VocabDeckFile`.
public struct VocabDeck: Deck {
    public let id: DeckID
    public let kind = DeckKind.vocab
    public let title: String
    public let subtitle: String
    public let subject: Subject
    public let entries: [VocabEntry]
    /// Every distinct tag, sorted.
    public let allTags: [String]

    public init(file: VocabDeckFile) {
        id = DeckID(file.deckId)
        title = file.title
        subtitle = file.subtitle
        subject = file.subject
        entries = file.entries.sorted { $0.rank < $1.rank }
        allTags = Array(Set(file.entries.flatMap(\.tags))).sorted()
    }

    public var defaultOptions: DeckOptions { .vocab(VocabOptions()) }

    /// `"<entryId>#<direction>"`.
    public static func itemKey(entryID: String, direction: VocabDirection) -> ItemKey {
        ItemKey("\(entryID)#\(direction.rawValue)")
    }

    public func cards(options: DeckOptions) -> [Card] {
        guard case let .vocab(o) = options else { return [] }
        let directions = o.direction.directions
        var result: [Card] = []
        result.reserveCapacity(entries.count * directions.count)
        for entry in entries where o.tags.isEmpty || entry.tags.contains(where: o.tags.contains) {
            for d in directions {
                result.append(Card(
                    key: Self.itemKey(entryID: entry.id, direction: d),
                    deckID: id,
                    content: .vocab(VocabPrompt(entry: entry, direction: d))
                ))
            }
        }
        return result
    }

    public func introductionRank(of card: Card) -> Int? { card.vocab?.entry.rank }

    public func newPerSession(options: DeckOptions) -> Int? { options.vocab?.newPerSession }

    /// Same entry (other direction) as previous ×0.1; tag shared with both of the previous 2 cards ×0.7.
    public func patternPenalty(candidate: Card, recent: ArraySlice<Card>) -> Double {
        guard let c = candidate.vocab else { return 1 }
        var penalty = 1.0
        guard let prev = recent.last?.vocab else { return penalty }
        if prev.entry.id == c.entry.id { penalty *= 0.1 }
        if recent.count >= 2, !c.entry.tags.isEmpty,
           let back2 = recent[recent.index(recent.endIndex, offsetBy: -2)].vocab,
           c.entry.tags.contains(where: { prev.entry.tags.contains($0) && back2.entry.tags.contains($0) }) {
            penalty *= 0.7
        }
        return penalty
    }
}
