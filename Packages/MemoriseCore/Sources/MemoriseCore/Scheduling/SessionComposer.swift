import Foundation

/// Coverage-first session composition for decks with introduction ranks (R8-S1, PLAN §10.5).
///
/// Definitions:
/// - **Entry:** all pool cards sharing one `introductionRank` (a vocab word's two directions).
/// - **Card state** (from `ItemStats`): `new` (never attempted), `wrong` (`lastAnswerWasWrong`),
///   otherwise `correct`.
/// - **Entry state:** `wrong` if any card is wrong; `fresh` if all cards are new; `partial` if some
///   are new and the rest correct; `covered` if all are correct.
/// - **Sessions since a miss:** completed sessions of the deck that started after the miss.
/// - **Wrong-card gap:** `wrongGapSessions.lowerBound + fnv1a("<key>|<lastWrongAt>") % width`,
///   random per miss but stable across launches. A wrong card is *due* once
///   `sessionsSinceMiss >= gap - 1`.
public enum SessionComposer {
    /// Gap in sessions for a card missed at `lastWrongAt` (2…4 by default).
    public static func wrongGap(key: ItemKey, lastWrongAt: Date, constants: SchedulerConstants) -> Int {
        let r = constants.wrongGapSessions
        let width = UInt64(max(1, r.upperBound - r.lowerBound + 1))
        return r.lowerBound + Int(stableHash("\(key.raw)|\(lastWrongAt.timeIntervalSince1970)") % width)
    }

    private struct Entry {
        var rank: Int
        var order: Int
        var keys: [ItemKey]
        var sortDate: Date = .distantPast
        var remaining = 0
    }

    /// Ordered queue of entries; each element holds the card keys of that entry to show this session.
    ///
    /// Order: ≤ `floor(targetEntries × share)` due wrong entries (`share` grows from `reviewShare` to `reviewShareMax` with the due backlog) (shuffled), fresh entries in
    /// rank order, partial entries, remaining due wrong entries, not-yet-due wrong entries (soonest
    /// first), covered entries (least recently seen first).
    ///
    /// - Parameter history: the deck's completed sessions. `.allDue` counts every wrong card as due; `.empty` none.
    /// - Returns: `nil` when the deck doesn't use coverage sessions or the pool has no ranks.
    public static func queue(
        pool: [Card],
        stats: [ItemKey: ItemStats],
        deck: any Deck,
        history: DeckHistory,
        targetEntries: Int,
        constants: SchedulerConstants = .standard,
        rng: inout SplitMix64
    ) -> [[ItemKey]]? {
        guard deck.usesCoverageSessions else { return nil }

        var byRank: [Int: [Card]] = [:]
        var ranks: [Int] = []
        var unranked: [Card] = []
        for card in pool {
            if let r = deck.introductionRank(of: card) {
                if byRank[r] == nil { ranks.append(r) }
                byRank[r, default: []].append(card)
            } else {
                unranked.append(card)
            }
        }
        guard !ranks.isEmpty else { return nil }
        ranks.sort()

        var groups: [(rank: Int, cards: [Card])] = ranks.map { ($0, byRank[$0]!) }
        for c in unranked { groups.append((Int.max, [c])) }

        var fresh: [Entry] = [], partial: [Entry] = [], covered: [Entry] = []
        var dueWrong: [Entry] = [], waiting: [Entry] = []

        for (order, group) in groups.enumerated() {
            var newCards: [Card] = [], wrongCards: [Card] = [], correctCards: [Card] = []
            for card in group.cards {
                if let s = stats[card.key], s.attempts > 0 {
                    if s.lastAnswerWasWrong { wrongCards.append(card) } else { correctCards.append(card) }
                } else {
                    newCards.append(card)
                }
            }
            var e = Entry(rank: group.rank, order: order, keys: [])
            if !wrongCards.isEmpty {
                var due: [ItemKey] = []
                var soonest = Int.max
                for card in wrongCards {
                    guard let missed = stats[card.key]?.lastWrongAt else { continue }
                    let left = wrongGap(key: card.key, lastWrongAt: missed, constants: constants) - 1 - history.sessionsSince(missed)
                    if left <= 0 { due.append(card.key) } else { soonest = min(soonest, left) }
                }
                if !due.isEmpty {
                    e.keys = due
                    dueWrong.append(e)
                } else {
                    e.keys = wrongCards.map(\.key)
                    e.remaining = soonest
                    waiting.append(e)
                }
            } else if newCards.count == group.cards.count {
                e.keys = [newCards.count == 1 ? newCards[0].key : newCards[Int.random(in: 0..<newCards.count, using: &rng)].key]
                fresh.append(e)
            } else if !newCards.isEmpty {
                e.keys = newCards.map(\.key)
                partial.append(e)
            } else {
                let oldest = correctCards.min { (stats[$0.key]?.lastSeenAt ?? .distantPast) < (stats[$1.key]?.lastSeenAt ?? .distantPast) }!
                e.keys = [oldest.key]
                e.sortDate = stats[oldest.key]?.lastSeenAt ?? .distantPast
                covered.append(e)
            }
        }

        dueWrong.shuffle(using: &rng)
        // The review share scales with the backlog (R7-4, owner option (a)): 0.3 with nothing due, up to 0.6 when
        // as many entries are due as the session has slots. The epsilon keeps exact products such as 20 × 0.45 = 9.
        let target = Double(max(targetEntries, 1))
        let share = constants.reviewShare + (constants.reviewShareMax - constants.reviewShare) * min(1, Double(dueWrong.count) / target)
        let reviewSlots = max(0, Int((target * share + 1e-9).rounded(.down)))
        let head = Array(dueWrong.prefix(reviewSlots))
        let tailDue = Array(dueWrong.dropFirst(reviewSlots))
        waiting.sort { ($0.remaining, $0.order) < ($1.remaining, $1.order) }
        covered.sort { ($0.sortDate, $0.order) < ($1.sortDate, $1.order) }

        return (head + fresh + partial + tailDue + waiting + covered).map(\.keys)
    }
}
