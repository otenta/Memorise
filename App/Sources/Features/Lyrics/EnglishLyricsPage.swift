import MemoriseCore
import SwiftUI

/// The English page: the Genius translation, else Apple's on-device translation line by line (PLAN_R10 O-2).
struct EnglishLyricsPage: View {
    let model: LyricsReaderViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                switch model.englishPage {
                case let .genius(english):
                    genius(english)
                case let .auto(lines):
                    auto(lines)
                case let .unavailable(needsLanguagePack):
                    unavailable(needsLanguagePack: needsLanguagePack)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .refreshable { await model.load(force: true) }
    }

    // MARK: Genius

    @ViewBuilder private func genius(_ english: [LyricLine]) -> some View {
        ForEach(english.indices, id: \.self) { i in
            let line = english[i]
            if line.isSectionHeader {
                header(line.text)
            } else if line.text.isEmpty {
                Color.clear.frame(height: 8)
            } else {
                Text(line.text).font(.title3)
            }
        }
        footer
    }

    // MARK: Auto-translated

    @ViewBuilder private func auto(_ lines: [AutoLine]) -> some View {
        Label("Auto-translated by Apple: no official translation was found", systemImage: "sparkles")
            .font(.footnote.weight(.medium))
            .foregroundStyle(.secondary)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.pink.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .accessibilityIdentifier("lyrics.english.autoBanner")
        ForEach(lines) { line in
            if line.isHeader {
                header(line.korean)
            } else if line.korean.isEmpty {
                Color.clear.frame(height: 8)
            } else {
                autoLine(line)
            }
        }
        footer
    }

    private func autoLine(_ line: AutoLine) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            switch line.english {
            case let .auto(text), let .genius(text):
                Text(text).font(.title3)
            case .pending:
                Capsule().fill(.primary.opacity(0.1)).frame(height: 18).padding(.vertical, 4)
            case .needsLanguagePack, .unavailable:
                Text("—").font(.title3).foregroundStyle(.tertiary)
            }
            Text(line.korean).font(.footnote).foregroundStyle(.secondary)
        }
        .padding(.bottom, 4)
        .accessibilityElement(children: .combine)
    }

    // MARK: Unavailable

    private func unavailable(needsLanguagePack: Bool) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "text.badge.xmark").font(.largeTitle).foregroundStyle(.secondary)
            Text("English translation not available").font(.headline)
            if needsLanguagePack {
                Text("Download Korean in Settings → Apps → Translate.")
                    .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("lyrics.englishUnavailable")
    }

    // MARK: Pieces

    private func header(_ text: String) -> some View {
        Text(text).font(.footnote.weight(.semibold)).foregroundStyle(.tertiary).padding(.top, 14)
    }

    @ViewBuilder private var footer: some View {
        if let footer = model.footer {
            Text(footer).font(.caption).foregroundStyle(.secondary).padding(.top, 24)
        }
    }
}
