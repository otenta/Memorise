import Foundation
import MemoriseCore
import SwiftUI

/// Display formatting helpers (pure, cheap).
enum Fmt {
    /// "2.3 s" / "850 ms".
    static func seconds(_ ms: Double?) -> String {
        guard let ms else { return "–" }
        return ms < 1_000 ? "\(Int(ms.rounded())) ms" : String(format: "%.1f s", ms / 1_000)
    }

    static func seconds(_ ms: Int) -> String { seconds(Double(ms)) }

    /// "87%".
    static func percent(_ v: Double?) -> String {
        guard let v else { return "–" }
        return "\(Int((v * 100).rounded()))%"
    }

    /// "4:05".
    static func clock(_ t: TimeInterval) -> String {
        let s = max(0, Int(t.rounded()))
        return s >= 3_600 ? String(format: "%d:%02d:%02d", s / 3_600, s / 60 % 60, s % 60) : String(format: "%d:%02d", s / 60, s % 60)
    }

    /// "2 days ago".
    static func relative(_ date: Date) -> String {
        date.formatted(.relative(presentation: .named, unitsStyle: .wide))
    }

    /// "▲ 120 ms" (slower) / "▼ 8%" style deltas. `lowerIsBetter` flips the color meaning.
    /// Single source of the display-rounding rule for "no change".
    static func isZeroDelta(ms: Double?) -> Bool {
        guard let ms else { return false }
        return abs(ms).rounded() == 0
    }

    static func isZeroDelta(percentPoints p: Double?) -> Bool {
        guard let p else { return false }
        return Int((abs(p) * 100).rounded()) == 0
    }

    /// "▲ 120 ms" / "▼ 1.2 s"; a zero delta renders "= 0 ms" without an arrow.
    static func delta(ms: Double?) -> String? {
        guard let ms else { return nil }
        if isZeroDelta(ms: ms) { return "= " + seconds(0.0) }
        return (ms > 0 ? "▲ " : "▼ ") + seconds(abs(ms))
    }

    /// "▲ 5 pt"; a zero delta renders "= 0 pt".
    static func delta(percentPoints: Double?) -> String? {
        guard let p = percentPoints else { return nil }
        if isZeroDelta(percentPoints: p) { return "= 0 pt" }
        return (p > 0 ? "▲ " : "▼ ") + "\(Int((abs(p) * 100).rounded())) pt"
    }
}

/// Human labels for cards (summary rows, lists).
enum CardLabel {
    @MainActor
    static func text(_ card: Card?, key: ItemKey, settings: AppSettings) -> String {
        guard let card else { return key.raw }
        switch card.content {
        case let .fretboardNote(p):
            return "\(NoteFormatter.format(p.spelling, settings: settings.musicDisplay)) · string \(p.stringNumber)"
        case let .vocab(p):
            return p.direction == .koToEn
                ? "\(p.entry.hangul) → \(p.entry.meaningText)"
                : "\(p.entry.meaningText) → \(p.entry.hangul)"
        }
    }
}

/// Color tokens.
enum Palette {
    static let correct = Color.green
    static let wrong = Color.red
    static let neutral = Color.secondary

    /// Response-time color vs. the item's history: green ≤ EWMA, yellow ≤ 1.3×, red otherwise.
    static func responseColor(ms: Int, prior: Double?) -> Color {
        guard let prior, prior > 0 else { return .secondary }
        let r = Double(ms) / prior
        return r <= 1 ? .green : (r <= 1.3 ? .yellow : .red)
    }

    /// Delta color: secondary when absent or zero, otherwise green (improvement) / red.
    static func deltaColor(_ v: Double?, lowerIsBetter: Bool, zero: (Double?) -> Bool) -> Color {
        guard let v, !zero(v) else { return .secondary }
        return (v < 0) == lowerIsBetter ? .green : .red
    }

    /// Fast → slow gradient for heatmaps. `ratio` = time / reference.
    static func heat(ratio: Double) -> Color {
        // log2 ratio in [-1, 1] → hue green (0.33) … red (0).
        let t = min(max((log2(max(ratio, 0.01)) + 1) / 2, 0), 1)
        return Color(hue: 0.33 * (1 - t), saturation: 0.75, brightness: 0.85)
    }
}
