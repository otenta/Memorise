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
            HStack {
                StatTile(title: "Learned", value: "\(m.learned)")
                StatTile(title: "Seen", value: "\(m.seen)")
                StatTile(title: "New", value: "\(m.new)")
            }
            .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
        }
        Section {
            if m.weakest.isEmpty {
                Text("Practise to find your weakest words.").foregroundStyle(.secondary)
            }
            ForEach(m.weakest) { item in
                if let v = item.card.vocab {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(v.entry.hangul).font(.headline)
                            Text(v.entry.meaningText).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(v.direction == .koToEn ? "KO → EN" : "EN → KO").font(.caption2.weight(.semibold))
                            Text("\(Fmt.percent(item.stats.accuracy)) · \(Fmt.seconds(item.stats.ewmaResponseMs))")
                                .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        } header: {
            Text("Weakest words")
        } footer: {
            Text("Ordered by how strongly the scheduler will favour them.")
        }
        .task(id: ModelKey(deck: deck.id, stats: stats)) {
            m = Self.makeModel(deck: deck, stats: stats)
        }
    }
}
