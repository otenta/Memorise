import Foundation

/// Monotonic time source: elapsed time since an arbitrary origin. Use for durations only.
public protocol MonotonicClock: Sendable {
    func now() -> Duration
}

/// Production clock backed by `ContinuousClock` (keeps counting while the device sleeps).
public struct ContinuousMonotonicClock: MonotonicClock {
    private let origin: ContinuousClock.Instant

    public init() { origin = ContinuousClock.now }

    public func now() -> Duration { origin.duration(to: ContinuousClock.now) }
}

/// Manually advanced clock for deterministic tests and previews.
public final class ManualClock: MonotonicClock, @unchecked Sendable {
    private let lock = NSLock()
    private var elapsed: Duration

    public init(_ start: Duration = .zero) { elapsed = start }

    public func now() -> Duration {
        lock.lock(); defer { lock.unlock() }
        return elapsed
    }

    public func advance(by d: Duration) {
        lock.lock(); defer { lock.unlock() }
        elapsed += d
    }
}

extension Duration {
    /// Whole milliseconds (truncated, never negative).
    @inlinable public var wholeMilliseconds: Int {
        let (s, atto) = components
        return max(0, Int(s) * 1_000 + Int(atto / 1_000_000_000_000_000))
    }
}
