import MemoriseCore
import Observation
import SwiftUI
@preconcurrency import Translation

/// One token of a Korean line with everything the token view draws, computed once per load / catalog change,
/// so the view reads nothing observable (PLAN_R10 LA2).
struct ReaderToken: Identifiable, Equatable {
    /// Index within the line.
    let id: Int
    let token: LyricToken
    let text: String
    /// Contains a Hangul syllable (O-3). `.plain` is never tappable.
    let isTappable: Bool
    /// The deck knows this word or phrase.
    let isDeckHit: Bool
}

/// One line of the Korean page, tokenised once per load / catalog change.
struct ReaderLine: Identifiable, Equatable {
    let id: Int
    let text: String
    let isHeader: Bool
    let tokens: [ReaderToken]
}

/// What the English page shows (PLAN_R10 O-2).
enum EnglishPage {
    /// The fetched Genius translation.
    case genius([LyricLine])
    /// Apple's on-device translation, line by line.
    case auto([AutoLine])
    case unavailable(needsLanguagePack: Bool)
}

/// One line of the auto-translated English page.
struct AutoLine: Identifiable {
    let id: Int
    let isHeader: Bool
    let korean: String
    let english: LineGloss
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
    /// Genius English by Korean line index, when the translation lines up one to one. Computed once per load.
    @ObservationIgnored private var alignedEnglish: [Int: String] = [:]
    @ObservationIgnored private var tokeniseTask: Task<Void, Never>?
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

    /// Whether Spotify's current song is the one open here: the same id, or the same title and artist (Spotify
    /// gives a relinked song another id per market or album).
    func isShowing(_ playback: SpotifyPlayback) -> Bool {
        playback.track.spotifyID == track.spotifyID
            || (TrackQuery.sameTitle(track.title, playback.track.title)
                && TrackQuery.sameArtist(track.primaryArtist, playback.track.primaryArtist))
    }

    var englishLines: [LyricLine]? { document?.english }

    var footer: String? {
        guard let document else { return nil }
        var parts = ["Lyrics: \(document.koreanSource)"]
        if let source = document.englishSource, document.english != nil {
            parts.append("Translation: \(source)")
        } else if document.english == nil, !glosses.languagePackMissing {
            parts.append("Translation: Apple (auto)")
        }
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
            alignedEnglish = Self.alignment(of: doc)
            await rebuildLines()
            phase = .ready(doc)
            await prepareGlosses(doc, force: force)
        case .result(.notAvailable):
            document = nil
            alignedEnglish = [:]
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
        tokeniseTask?.cancel()
        tokeniseTask = Task { await rebuildLines() }
    }

    /// Songs longer than this are tokenised off the main actor.
    private static let backgroundTokeniseLines = 80

    private func rebuildLines() async {
        guard let document else { return }
        let lookup = glosses.wordLookup
        let source = document.korean
        let built: [ReaderLine]
        if source.count > Self.backgroundTokeniseLines {
            built = await Task.detached(priority: .userInitiated) { Self.buildLines(source, lookup: lookup) }.value
        } else {
            built = Self.buildLines(source, lookup: lookup)
        }
        guard !Task.isCancelled else { return }
        lines = built
    }

    nonisolated private static func buildLines(_ source: [LyricLine], lookup: WordLookup) -> [ReaderLine] {
        source.enumerated().map { i, line in
            let tokens = LyricsTokenizer.tokens(for: line, phrases: lookup.phrases).enumerated().map { j, token in
                let text: String
                switch token {
                case let .word(t, _): text = t
                case let .phrase(t, _, _): text = t
                case let .plain(t): text = t
                }
                var tappable = true
                if case .plain = token { tappable = false }
                tappable = tappable && GlossText.containsHangul(text)
                return ReaderToken(id: j, token: token, text: text, isTappable: tappable,
                                   isDeckHit: tappable && lookup.lookup(token) != nil)
            }
            return ReaderLine(id: i, text: line.text, isHeader: line.isSectionHeader, tokens: tokens)
        }
    }

    nonisolated private static func alignment(of doc: LyricsDocument) -> [Int: String] {
        guard let english = doc.english, let pairs = TranslationAlignment.pairs(korean: doc.korean, english: english) else { return [:] }
        return Dictionary(pairs.map { ($0.koreanIndex, $0.en) }, uniquingKeysWith: { first, _ in first })
    }

    private func prepareGlosses(_ doc: LyricsDocument, force: Bool) async {
        // Every bubble already has its Genius line when the English lines up with the Korean one to one.
        let needsLines = alignedEnglish.isEmpty
        await glosses.prepare(document: doc, track: trackID, needsLines: needsLines)
        guard glosses.hasPending(track: trackID) else { return }
        if force { glosses.retryFailed(track: trackID) }
        if translation == nil {
            translation = TranslationSession.Configuration(source: GlossService.source, target: GlossService.target)
        } else {
            translation?.invalidate()
        }
    }

    // MARK: Bubble

    func meaning(for token: LyricToken) -> GlossState { glosses.meaning(for: token, track: trackID) }

    /// The line's meaning: the aligned Genius line, else Apple's translation of it.
    func lineMeaning(for line: ReaderLine) -> LineGloss {
        if let genius = alignedEnglish[line.id] { return .genius(genius) }
        return glosses.lineMeaning(line.text, track: trackID) ?? .unavailable
    }

    /// The English page: Genius when the document has it, else Apple's translation line by line.
    var englishPage: EnglishPage {
        guard let document else { return .unavailable(needsLanguagePack: false) }
        if let english = document.english, !english.isEmpty { return .genius(english) }
        if glosses.languagePackMissing { return .unavailable(needsLanguagePack: true) }
        let auto = document.korean.enumerated().map { i, line -> AutoLine in
            let gloss: LineGloss
            if line.isSectionHeader || !GlossText.containsHangul(line.text) {
                gloss = .auto(line.text)
            } else {
                gloss = glosses.lineMeaning(line.text, track: trackID) ?? .unavailable
            }
            return AutoLine(id: i, isHeader: line.isSectionHeader, korean: line.text, english: gloss)
        }
        return .auto(auto)
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
        case .pending, .needsLanguagePack, .noWordMeaning: break
        }
        let english = alignedEnglish[line.id]
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
