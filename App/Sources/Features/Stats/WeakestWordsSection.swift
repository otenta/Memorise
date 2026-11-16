import MemoriseCore
import SwiftUI

/// Learned / Seen / New counts and the weakest items by scheduler weight (§11.6).
struct WeakestWordsSection: View {
    let deck: VocabDeck
    let stats: [ItemKey: ItemStats]

    @State private var m = Model()

    private struct Model {
        var learned = 0
        var seen = 0
        var new = 0
        var weakest: [Weak] = []
    }

    private struct Weak: Identifiable {
        let card: Card
        let stats: ItemStats
        var id: ItemKey { card.key }
    }

    /// Learned = ≥ 3 attempts and error EWMA < 0.2.
    private static func makeModel(deck: VocabDeck, stats: [ItemKey: ItemStats]) -> Model {
        let pool = deck.cards(options: .vocab(VocabOptions(direction: .both)))
        let calc = WeightCalculator(pool: pool, stats: stats, focus: .normal, now: .now)
        var m = Model()
        var scored: [(Weak, Double)] = []
        for card in pool {
            guard let s = stats[card.key], s.attempts > 0 else { m.new += 1; continue }
            if s.attempts >= 3 && s.ewmaError < 0.2 { m.learned += 1 } else { m.seen += 1 }
            scored.append((Weak(card: card, stats: s), calc.baseWeight(s)))
        }
        scored.sort { $0.1 > $1.1 }
        m.weakest = scored.prefix(20).map(\.0)
        return m
    }

    private struct ModelKey: Equatable {
        let deck: DeckID
        let stats: [ItemKey: ItemStats]
    }

    var body: some View {
        Section("Progress") {
            VStack(spacing: 12) {
                HStack(spacing: 10) {
                    StatTile(title: "Learned", value: "\(m.learned)", systemImage: "checkmark.seal.fill", tint: Theme.mint)
                    StatTile(title: "Seen", value: "\(m.seen)", systemImage: "eye.fill", tint: Theme.amber)
                    StatTile(title: "New", value: "\(m.new)", systemImage: "sparkles", tint: Theme.pink)
                }
                masteryBar
            }
            .animation(Theme.softSpring, value: m.learned)
            .animation(Theme.softSpring, value: m.seen)
            .listRowInsets(EdgeInsets(top: 8, leading: 4, bottom: 8, trailing: 4))
            .listRowBackground(Color.clear)
        }
        Section {
            if m.weakest.isEmpty {
                Label("Practise to find your weakest words.", systemImage: "magnifyingglass")
                    .foregroundStyle(.secondary)
            }
            ForEach(Array(m.weakest.enumerated()), id: \.element.id) { rank, item in
                if let v = item.card.vocab {
                    WeakRow(rank: rank + 1, prompt: v, stats: item.stats)
                }
            }
        } header: {
            Text("Weakest words")
        } footer: {
            Text("Ordered by how strongly the scheduler will favour them.")
        }
        .task(id: ModelKey(deck: deck.id, stats: stats)) {
            withAnimation(Theme.softSpring) { m = Self.makeModel(deck: deck, stats: stats) }
        }
    }

    /// Stacked learned / seen / new bar.
    private var masteryBar: some View {
        let total = max(1, m.learned + m.seen + m.new)
        return VStack(alignment: .leading, spacing: 6) {
            GeometryReader { geo in
                let w = geo.size.width
                HStack(spacing: 2) {
                    segment(Theme.correctGradient, width: w * CGFloat(m.learned) / CGFloat(total))
                    segment(LinearGradient(colors: [Theme.amber, .orange], startPoint: .leading, endPoint: .trailing),
                            width: w * CGFloat(m.seen) / CGFloat(total))
                    segment(LinearGradient(colors: [Color.gray.opacity(0.25)], startPoint: .leading, endPoint: .trailing),
                            width: w * CGFloat(m.new) / CGFloat(total))
                }
            }
            .frame(height: 10)
            .clipShape(Capsule())
            Text("\(Int((Double(m.learned) / Double(total) * 100).rounded()))% of the deck learned")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .contentTransition(.numericText())
        }
        .padding(14)
        .glassCard(radius: 18, tint: Theme.mint)
        .accessibilityElement(children: .combine)
    }

    private func segment(_ fill: LinearGradient, width: CGFloat) -> some View {
        Rectangle().fill(fill).frame(width: max(0, width - 2))
    }
}

/// One ranked weak-word row.
private struct WeakRow: View {
    let rank: Int
    let prompt: VocabPrompt
    let stats: ItemStats

    var body: some View {
        let accuracy = stats.accuracy ?? 0
        let accColor: Color = accuracy >= 0.8 ? Theme.mint : (accuracy >= 0.5 ? Theme.amber : Theme.rose)
        HStack(spacing: 12) {
            Text("\(rank)")
                .font(.system(.caption, design: .rounded, weight: .heavy).monospacedDigit())
                .foregroundStyle(rank <= 3 ? .white : .secondary)
                .frame(width: 26, height: 26)
                .background {
                    Circle().fill(rank <= 3 ? AnyShapeStyle(Subject.korean.gradient) : AnyShapeStyle(Color.primary.opacity(0.07)))
                }
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(prompt.entry.hangul)
                        .font(.system(.headline, weight: .bold))
                        .foregroundStyle(Subject.korean.gradient)
                    Text(prompt.direction == .koToEn ? "KO→EN" : "EN→KO")
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(.primary.opacity(0.07), in: Capsule())
                }
                Text(prompt.entry.meaningText).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 5) {
                Text(Fmt.percent(stats.accuracy))
                    .font(.system(.subheadline, design: .rounded, weight: .bold).monospacedDigit())
                    .foregroundStyle(accColor)
                Capsule().fill(.primary.opacity(0.08))
                    .frame(width: 54, height: 5)
                    .overlay(alignment: .leading) {
                        Capsule().fill(accColor.gradient).frame(width: 54 * accuracy)
                    }
                Text(Fmt.seconds(stats.ewmaResponseMs))
                    .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}
