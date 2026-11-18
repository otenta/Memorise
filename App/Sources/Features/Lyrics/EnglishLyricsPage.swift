import MemoriseCore
import SwiftUI

/// The English page: the fetched translation as it is, or a note when none was found (L-D6).
struct EnglishLyricsPage: View {
    let model: LyricsReaderViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                if let english = model.englishLines, !english.isEmpty {
                    ForEach(Array(english.enumerated()), id: \.offset) { _, line in
                        if line.isSectionHeader {
                            Text(line.text)
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.tertiary)
                                .padding(.top, 14)
                        } else if line.text.isEmpty {
                            Color.clear.frame(height: 8)
                        } else {
                            Text(line.text).font(.title3)
                        }
                    }
                    if let footer = model.footer {
                        Text(footer).font(.caption).foregroundStyle(.secondary).padding(.top, 24)
                    }
                } else {
                    VStack(spacing: 10) {
                        Image(systemName: "text.badge.xmark").font(.largeTitle).foregroundStyle(.secondary)
                        Text("English translation not available").font(.headline)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 80)
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("lyrics.englishUnavailable")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .refreshable { await model.load(force: true) }
    }
}
