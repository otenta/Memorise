/// Small descriptive-statistics helpers.
public enum Statistics {
    public static func mean(_ values: some Collection<Double>) -> Double? {
        values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
    }

    public static func median(_ values: some Collection<Double>) -> Double? {
        percentile(values, 0.5)
    }

    /// Percentile `p` ∈ [0, 1] with linear interpolation between closest ranks.
    public static func percentile(_ values: some Collection<Double>, _ p: Double) -> Double? {
        guard !values.isEmpty else { return nil }
        return percentile(sorted: values.sorted(), p)
    }

    /// Same as `percentile` for already-sorted input (avoids re-sorting).
    public static func percentile(sorted: [Double], _ p: Double) -> Double? {
        guard let first = sorted.first else { return nil }
        guard sorted.count > 1 else { return first }
        let pos = min(max(p, 0), 1) * Double(sorted.count - 1)
        let lo = Int(pos)
        let hi = min(lo + 1, sorted.count - 1)
        let frac = pos - Double(lo)
        return sorted[lo] + (sorted[hi] - sorted[lo]) * frac
    }
}
