import Foundation

/// Start times of a deck's completed sessions, oldest first (R8-S1). Discarded sessions leave no
/// record and killed sessions with fewer than 5 counted cards are abandoned (R9-SF2), so neither appears here.
public struct DeckHistory: Sendable, Hashable {
    public let completedSessionStarts: [Date]
    /// `.allDue` only: every wrong card counts as due, whatever its miss time.
    private let isAllDue: Bool

    /// No completed sessions: a card missed in this session isn't due yet.
    public static let empty = DeckHistory(completedSessionStarts: [])

    /// "Enough sessions have passed for every miss": every wrong card is due. For callers without session
    /// history (previews, tools); the choice is explicit, never an accident of passing nothing.
    public static let allDue = DeckHistory(completedSessionStarts: [], isAllDue: true)

    /// `starts` need not be sorted.
    public init(completedSessionStarts starts: [Date]) {
        self.init(completedSessionStarts: starts, isAllDue: false)
    }

    private init(completedSessionStarts starts: [Date], isAllDue: Bool) {
        completedSessionStarts = starts.sorted()
        self.isAllDue = isAllDue
    }

    /// Completed sessions that started after `date` (binary search). `Int.max` for `.allDue`.
    public func sessionsSince(_ date: Date) -> Int {
        if isAllDue { return .max }
        var lo = 0, hi = completedSessionStarts.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if completedSessionStarts[mid] > date { hi = mid } else { lo = mid + 1 }
        }
        return completedSessionStarts.count - lo
    }
}
