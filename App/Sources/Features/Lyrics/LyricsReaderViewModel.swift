import MemoriseCore
import Observation
import SwiftUI
@preconcurrency import Translation

/// One line of the Korean page, tokenised once per load / catalog change.
struct ReaderLine: Identifiable {
    let id: Int
    let text: String
    let isHeader: Bool
    let tokens: [LyricToken]
}

/// A tapped word, ready for the "Add to deck" sheet (L8).
struct LyricAddCandidate: Identifiable {
    let id = UUID()
    let track: TrackInfo
    /// What was tapped (a word or a phrase).
    let tapped: String
    /// Deck hit, when the word is already in a deck.
    let hit: VocabEntry?
    /// Bubble meaning (deck meaning or auto-translation), empty when unknown.
    let meaning: String
    /// The full lyric line.
    let line: String
    /// The aligned English line, when the translation lines up one to one.
    let englishLine: String?
}

/// State of the lyrics reader (PLAN_M6 §4.4, §4.8, L7).
@MainActor @Observable
final class LyricsReaderViewModel {
    enum Phase {
        case loading
        case ready(LyricsDocument)
        /// "Lyrics not available for this track" (every reason, L-D7).
        case notAvailable
        case offline
        case failed(String)
    }

    private(set) var track: TrackInfo
    private(set) var phase: Phase = .loading
    private(set) var lines: [ReaderLine] = []
    var adding: LyricAddCandidate?
    private(set) var toast: String?
    /// Drives `.translationTask`; `nil` until the song has words that need Apple's Translation.
    var translation: TranslationSession.Configuration?

    @ObservationIgnored private let lyrics: LyricsService
    @ObservationIgnored private let spotify: SpotifyClient
    @ObservationIgnored private let glosses: GlossService
    @ObservationIgnored private var document: LyricsDocument?
    @ObservationIgnored private var toastTask: Task<Void, Never>?

    init(track: TrackInfo, lyrics: LyricsService, spotify: SpotifyClient, glosses: GlossService) {
        self.track = track
        self.lyrics = lyrics
        self.spotify = spotify
        self.glosses = glosses
    }

    var trackID: String { track.spotifyID }

    var isAvailable: Bool {
        if case .ready = phase { return true }
        return false
    }

    var englishLines: [LyricLine]? { document?.english }

    var footer: String? {
        guard let document else { return nil }
        var parts = ["Lyrics: \(document.koreanSource)"]
        if let source = document.englishSource, document.english != nil { parts.append("Translation: \(source)") }
        return parts.joined(separator: " · ")
    }

    // MARK: Loading

    func load(force: Bool = false) async {
        if !isAvailable { phase = .loading }
        let spotify = spotify
        let (outcome, resolved) = await lyrics.lyrics(for: track, forceRefresh: force) { await spotify.koreanTitle(of: $0) }
        track = resolved
        switch outcome {
        case let .result(.available(doc)):
            document = doc
            tokenise()
            phase = .ready(doc)
            await prepareGlosses(doc, force: force)
        case .result(.notAvailable):
            document = nil
            lines = []
            phase = .notAvailable
        case .offline:
            // Keep what is on screen when a refresh fails offline.
            if !isAvailable { phase = .offline }
        case let .failed(message):
            if !isAvailable { phase = .failed(message) }
        }
    }

    /// Re-splits the lines (a word was added, so a new phrase may match).
    func tokenise() {
        guard let document else { return }
        let phrases = glosses.wordLookup.phrases
        lines = document.korean.enumerated().map { i, line in
            ReaderLine(id: i, text: line.text, isHeader: line.isSectionHeader,
                       tokens: LyricsTokenizer.tokens(for: line, phrases: phrases))
        }
    }

    private func prepareGlosses(_ doc: LyricsDocument, force: Bool) async {
        await glosses.prepare(document: doc, track: trackID)
        guard !glosses.pendingTexts(track: trackID).isEmpty else { return }
        if force { glosses.retryFailed(track: trackID) }
        if translation == nil {
            translation = TranslationSession.Configuration(source: GlossService.source, target: GlossService.target)
        } else {
            translation?.invalidate()
        }
    }

    // MARK: Bubble

    func meaning(for token: LyricToken) -> GlossState { glosses.meaning(for: token, track: trackID) }

    func isKnown(_ token: LyricToken) -> Bool {
        if case .deck = glosses.meaning(for: token, track: trackID) { return true }
        return false
    }

    func candidate(for token: LyricToken, in line: ReaderLine) -> LyricAddCandidate {
        let tapped: String
        switch token {
        case let .word(text, _): tapped = text
        case let .phrase(text, _, _): tapped = text
        case let .plain(text): tapped = text
        }
        var hit: VocabEntry?
        var meaning = ""
        switch glosses.meaning(for: token, track: trackID) {
        case let .deck(entry, _, _): hit = entry; meaning = entry.meaningText
        case let .auto(text): meaning = text
        case .pending, .unavailable: break
        }
        let english = document.flatMap { TranslationAlignment.englishLine(forKoreanLineAt: line.id, in: $0) }
        return LyricAddCandidate(track: track, tapped: tapped, hit: hit, meaning: meaning, line: line.text, englishLine: english)
    }

    // MARK: Toast

    func showToast(_ text: String) {
        toast = text
        toastTask?.cancel()
        toastTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2.2))
            guard !Task.isCancelled else { return }
            self?.toast = nil
        }
    }
}
