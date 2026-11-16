/// Fast, seedable 64-bit PRNG (SplitMix64). Deterministic for a given seed.
public struct SplitMix64: RandomNumberGenerator, Sendable, Hashable {
    public var state: UInt64

    public init(seed: UInt64) { state = seed }

    /// Seeds from the system generator (non-deterministic).
    public init() {
        var g = SystemRandomNumberGenerator()
        state = g.next()
    }

    @inlinable public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z &>> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z &>> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z &>> 31)
    }
}
