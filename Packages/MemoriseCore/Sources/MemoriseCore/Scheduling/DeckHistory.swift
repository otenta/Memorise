import Foundation

/// Start times of a deck's completed sessions, oldest first (R8-S1). Discarded sessions leave no
/// record and killed sessions aren't `.completed`, so neither appears here.
public struct DeckHistory: Sendable, Hashable {
    public let completedSessionStarts: [Date]

    public static let empty = DeckHistory(completedSessionStarts: [])

    /// `starts` need not be sorted.
    public init(completedSessionStarts starts: [Date]) {
        completedSessionStarts = starts.sorted()
    }

    /// Completed sessions that started after `date` (binary search).
    public func sessionsSince(_ date: Date) -> Int {
        var lo = 0, hi = completedSessionStarts.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if completedSessionStarts[mid] > date { hi = mid } else { lo = mid + 1 }
        }
        return completedSessionStarts.count - lo
    }
}
