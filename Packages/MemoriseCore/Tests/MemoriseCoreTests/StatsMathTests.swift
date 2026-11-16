import Foundation
import Testing
@testable import MemoriseCore

/// PLAN §9.4 (stats update), §9.5 helpers, §10.2 (base weight).
@Suite("Stats maths (§9.4, §10.2)")
struct StatsMathTests {
    let key: ItemKey = "fret:s6:A"
    let deck = FretboardNotesDeck.deckID

    // MARK: Statistics

    @Test func meanMedianPercentile() {
        #expect(Statistics.mean([Double]()) == nil)
        #expect(Statistics.median([Double]()) == nil)
        #expect(Statistics.mean([1, 2, 3, 4]) == 2.5)
        #expect(Statistics.median([5]) == 5)
        #expect(Statistics.median([3, 1, 2]) == 2)
        #expect(Statistics.median([4, 1, 3, 2]) == 2.5)
        #expect(Statistics.percentile([1, 2, 3, 4, 5, 6, 7, 8, 9, 10], 0.9)! == 9.1)
        #expect(Statistics.percentile([10, 20], 0)! == 10)
        #expect(Statistics.percentile([10, 20], 1)! == 20)
        #expect(Statistics.percentile([10, 20], 2)! == 20)   // p clamped
        #expect(Statistics.percentile([10, 20], -1)! == 10)
        #expect(Statistics.percentile(sorted: [], 0.5) == nil)
    }

    // MARK: StatsUpdater

    @Test func firstCorrectAttemptSeedsEwma() {
        let s = StatsUpdater.apply(responseMs: 1_200, correct: true, at: fixedNow, to: .empty(key: key, deck: deck))
        #expect(s.attempts == 1)
        #expect(s.correctCount == 1)
        #expect(s.ewmaResponseMs == 1_200)
        #expect(s.bestResponseMs == 1_200)
        #expect(s.ewmaError == 0)
        #expect(s.lastSeenAt == fixedNow)
        #expect(s.lastWrongAt == nil)
        #expect(s.accuracy == 1)
    }

    @Test func correctAttemptUpdatesEwmaWithAlpha() {
        var s = ItemStats(itemKey: key, deckID: deck, attempts: 1, correctCount: 1, ewmaResponseMs: 2_000, ewmaError: 0.5, bestResponseMs: 2_000)
        s = StatsUpdater.apply(responseMs: 1_000, correct: true, at: fixedNow, to: s)
        #expect(abs(s.ewmaResponseMs! - (0.3 * 1_000 + 0.7 * 2_000)) < 1e-9)
        #expect(abs(s.ewmaError - 0.35) < 1e-12)
        #expect(s.bestResponseMs == 1_000)
    }

    @Test func wrongAttemptNeverTouchesTimeEwma() {
        let before = ItemStats(itemKey: key, deckID: deck, attempts: 2, correctCount: 2, ewmaResponseMs: 2_000, ewmaError: 0.1, bestResponseMs: 1_800)
        let s = StatsUpdater.apply(responseMs: 200, correct: false, at: fixedNow, to: before)
        #expect(s.ewmaResponseMs == 2_000)
        #expect(s.bestResponseMs == 1_800)
        #expect(s.attempts == 3)
        #expect(s.correctCount == 2)
        #expect(abs(s.ewmaError - (0.3 + 0.7 * 0.1)) < 1e-12)
        #expect(s.lastWrongAt == fixedNow)
        #expect(s.lastSeenAt == fixedNow)
    }

    @Test func responseTimesAreClampedForMathsOnly() {
        let fast = StatsUpdater.apply(responseMs: 20, correct: true, at: fixedNow, to: .empty(key: key, deck: deck))
        #expect(fast.ewmaResponseMs == 150)
        #expect(fast.bestResponseMs == 150)
        let slow = StatsUpdater.apply(responseMs: 90_000, correct: true, at: fixedNow, to: .empty(key: key, deck: deck))
        #expect(slow.ewmaResponseMs == 30_000)
        #expect(SchedulerConstants.standard.clamp(149) == 150)
        #expect(SchedulerConstants.standard.clamp(30_001) == 30_000)
        #expect(SchedulerConstants.standard.clamp(5_000) == 5_000)
    }

    @Test func attemptConvenienceIgnoresRetriesAndInterruptions() {
        let empty = ItemStats.empty(key: key, deck: deck)
        let sid = UUID()
        #expect(StatsUpdater.apply(attempt(session: sid, key: key, index: 0, isRetry: true), at: fixedNow, to: empty) == empty)
        #expect(StatsUpdater.apply(attempt(session: sid, key: key, index: 0, interrupted: true), at: fixedNow, to: empty) == empty)
        #expect(StatsUpdater.apply(attempt(session: sid, key: key, index: 0), at: fixedNow, to: empty).attempts == 1)
    }

    @Test func constantsMatchSpec() {
        let c = SchedulerConstants.standard
        #expect(c.alphaTime == 0.3 && c.alphaError == 0.3)
        #expect(c.minResponseMs == 150 && c.maxResponseMs == 30_000)
        #expect(c.fallbackReferenceMs == 4_000)
        #expect(c.minRatio == 0.33 && c.maxRatio == 4)
        #expect(c.newCardWeight == 1.5 && c.weightFloor == 0.05)
        #expect(c.alreadyShownFactor == 0.2 && c.maxCooldown == 3)
        #expect(c.retryDelay == 3...5)
        #expect(c.gradeLockoutMs == 250)
    }

    // MARK: WeightCalculator (§10.2)

    private func calc(_ focus: FocusLevel = .normal, pool: [Card] = fretboardCards(), stats: [ItemKey: ItemStats] = [:], constants: SchedulerConstants = .standard) -> WeightCalculator {
        WeightCalculator(pool: pool, stats: stats, focus: focus, now: fixedNow, constants: constants)
    }

    @Test func referenceIsMedianOfPoolEwmaOrFallback() {
        let pool = fretboardCards()
        #expect(calc(pool: pool).referenceMs == 4_000)
        let stats = Dictionary(uniqueKeysWithValues: zip(pool.prefix(3), [1_000.0, 3_000, 2_000]).map { ($0.key, seenStats($0.key, ewma: $1)) })
        #expect(calc(pool: pool, stats: stats).referenceMs == 2_000)
    }

    @Test func unseenAndOffFocus() {
        let c = calc()
        #expect(c.baseWeight(nil) == 1.5)
        #expect(c.baseWeight(ItemStats.empty(key: key, deck: deck)) == 1.5)
        #expect(calc(.off).baseWeight(seenStats(key, ewma: 30_000, error: 1)) == 1)
        #expect(calc(.off).baseWeight(nil) == 1)
    }

    @Test func weightFormulaComponents() {
        // ref = fallback 4000 (pool stats not passed); attempts 1 → unc 2; lastSeen now → stale 1.
        let c = calc()
        func w(ewma: Double?, error: Double = 0, attempts: Int = 1, lastSeen: Date? = fixedNow) -> Double {
            c.baseWeight(seenStats(key, ewma: ewma, error: error, attempts: attempts, lastSeen: lastSeen))
        }
        #expect(abs(w(ewma: 4_000) - 2) < 1e-9)
        #expect(abs(w(ewma: nil) - 2) < 1e-9)                                    // missing ewma → ref
        #expect(abs(w(ewma: 12_000) - pow(3, 1.5) * 2) < 1e-9)                   // ratio 3
        #expect(abs(w(ewma: 400_000) - pow(4, 1.5) * 2) < 1e-9)                  // ratio clamped to 4
        #expect(abs(w(ewma: 4_000, error: 0.5) - 2.5 * 2) < 1e-9)                // err = 1 + 3·0.5
        #expect(abs(w(ewma: 4_000, attempts: 4) - 1.25) < 1e-9)                  // unc = 1 + 1/4
        #expect(abs(w(ewma: 4_000, lastSeen: fixedNow.addingTimeInterval(-7 * 86_400)) - 3) < 1e-9)  // stale 1.5
        #expect(abs(w(ewma: 4_000, lastSeen: fixedNow.addingTimeInterval(-60 * 86_400)) - 4) < 1e-9) // stale capped at 2
        #expect(abs(w(ewma: 4_000, lastSeen: fixedNow.addingTimeInterval(86_400)) - 2) < 1e-9)       // future → 0 days
        #expect(abs(calc(.strong).baseWeight(seenStats(key, ewma: 8_000, error: 0.2, attempts: 1)) - pow(2, 2.5) * 2 * 2) < 1e-9)
    }

    @Test func weightFloor() {
        var k = SchedulerConstants()
        k.minRatio = 0.001
        let c = calc(.strong, constants: k)
        #expect(c.baseWeight(seenStats(key, ewma: 150, attempts: 1_000_000)) == 0.05)
    }
}
