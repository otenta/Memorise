import Foundation

/// Tunables for the Lyrics feature (PLAN_M6 §4.3, §4.7).
public enum LyricsConstants {
    /// Minimum Hangul share (Hangul ÷ Hangul + Latin) for lyrics to count as Korean. Low on purpose:
    /// many K-pop songs are half English.
    public static let minHangulShare = 0.25
    /// Minimum number of Hangul syllables for lyrics to count as Korean.
    public static let minHangulSyllables = 20
    /// How long a "not available" cache entry is trusted before it is fetched again.
    public static let notAvailableTTLDays = 7
    /// Requests for the Korean lyrics: 2 × LRCLIB get + 1 search + 2 × (Genius search + page). A unit may include
    /// one retry after a server error.
    public static let koreanRequestBudget = 7
    /// Requests for the English page: search + page + 1 spare.
    public static let englishRequestBudget = 3
    /// A cached document without an English page is looked up again after this many days.
    public static let missingEnglishTTLDays = 7
}

/// A Spotify track, as the picker and the reader see it.
public struct TrackInfo: Hashable, Codable, Sendable {
    /// "11dFghVXANMlKmJXsNCbNl".
    public var spotifyID: String
    /// Title as Spotify returned it.
    public var title: String
    /// Title from the `ko-KR` request (§4.4), only when it differs from `title`.
    public var titleKo: String?
    /// Primary artist first.
    public var artists: [String]
    public var album: String
    public var durationMs: Int
    /// First four characters of the album's release date.
    public var releaseYear: Int?
    /// Smallest artwork image that is at least 64 px wide.
    public var artworkURL: String?

    public init(
        spotifyID: String, title: String, titleKo: String? = nil, artists: [String] = [], album: String = "",
        durationMs: Int = 0, releaseYear: Int? = nil, artworkURL: String? = nil
    ) {
        self.spotifyID = spotifyID
        self.title = title
        self.titleKo = titleKo
        self.artists = artists
        self.album = album
        self.durationMs = durationMs
        self.releaseYear = releaseYear
        self.artworkURL = artworkURL
    }

    private enum CodingKeys: String, CodingKey {
        case spotifyID, title, titleKo, artists, album, durationMs, releaseYear, artworkURL
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        spotifyID = (try? c.decodeIfPresent(String.self, forKey: .spotifyID)) ?? ""
        title = (try? c.decodeIfPresent(String.self, forKey: .title)) ?? ""
        titleKo = try? c.decodeIfPresent(String.self, forKey: .titleKo)
        artists = (try? c.decodeIfPresent([String].self, forKey: .artists)) ?? []
        album = (try? c.decodeIfPresent(String.self, forKey: .album)) ?? ""
        durationMs = (try? c.decodeIfPresent(Int.self, forKey: .durationMs)) ?? 0
        releaseYear = try? c.decodeIfPresent(Int.self, forKey: .releaseYear)
        artworkURL = try? c.decodeIfPresent(String.self, forKey: .artworkURL)
    }

    /// First artist, or "".
    public var primaryArtist: String { artists.first ?? "" }

    /// "Artist, Artist".
    public var artistLine: String { artists.joined(separator: ", ") }

    /// Korean title when there is one, else the title.
    public var displayTitle: String { titleKo ?? title }
}

/// One display line of lyrics.
public struct LyricLine: Hashable, Codable, Sendable {
    /// One display line, trimmed.
    public var text: String
    /// Genius "[Chorus]" etc.: shown dimmed, never tokenised.
    public var isSectionHeader: Bool

    public init(text: String, isSectionHeader: Bool = false) {
        self.text = text
        self.isSectionHeader = isSectionHeader
    }

    private enum CodingKeys: String, CodingKey { case text, isSectionHeader }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        text = (try? c.decodeIfPresent(String.self, forKey: .text)) ?? ""
        isSectionHeader = (try? c.decodeIfPresent(Bool.self, forKey: .isSectionHeader)) ?? false
    }
}

/// Fetched lyrics for one track. Never bundled, never exported (PLAN_M6 copyright rule).
public struct LyricsDocument: Hashable, Codable, Sendable {
    public var korean: [LyricLine]
    /// `nil` = "English translation not available".
    public var english: [LyricLine]?
    /// "LRCLIB" or "Genius".
    public var koreanSource: String
    /// "Genius".
    public var englishSource: String?

    public init(korean: [LyricLine], english: [LyricLine]? = nil, koreanSource: String, englishSource: String? = nil) {
        self.korean = korean
        self.english = english
        self.koreanSource = koreanSource
        self.englishSource = englishSource
    }

    private enum CodingKeys: String, CodingKey { case korean, english, koreanSource, englishSource }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        korean = (try? c.decodeIfPresent([LyricLine].self, forKey: .korean)) ?? []
        english = try? c.decodeIfPresent([LyricLine].self, forKey: .english)
        koreanSource = (try? c.decodeIfPresent(String.self, forKey: .koreanSource)) ?? ""
        englishSource = try? c.decodeIfPresent(String.self, forKey: .englishSource)
    }
}

/// What the provider chain found for a track.
public enum LyricsResult: Hashable, Sendable {
    case available(LyricsDocument)
    /// The UI shows one message ("Lyrics not available for this track") for every reason.
    case notAvailable(Reason)

    public enum Reason: String, Sendable, Codable {
        case notFound, instrumental, notKorean
    }
}

/// One tappable (or plain) piece of a lyric line.
public enum LyricToken: Hashable, Sendable {
    /// A tappable eojeol, punctuation trimmed. `range` is the Character offset range of `text` within the line.
    case word(text: String, range: Range<Int>)
    /// A multi-word deck entry. `tokenRange` indexes the line's tokens *before* phrase merging
    /// (the words it replaced, as returned by `LyricsTokenizer.wordTokens`).
    case phrase(text: String, entryID: String, tokenRange: ClosedRange<Int>)
    /// Latin text, numbers, punctuation, "(", "~": not tappable.
    case plain(String)
}
