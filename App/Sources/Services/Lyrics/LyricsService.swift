import Foundation
import MemoriseCore

/// What `LyricsService.lyrics(for:forceRefresh:)` found.
enum LyricsOutcome: Sendable {
    case result(LyricsResult)
    /// No connection and nothing cached.
    case offline
    case failed(String)
}

/// Finds Hangul lyrics and an English translation for a track, with an on-device cache (PLAN_M6 §4.4).
/// Hangul: LRCLIB `get`, LRCLIB `search`, then Genius. English: Genius "English Translation" pages.
/// Never throws for a missing translation. At most 5 requests per song.
final class LyricsService: Sendable {
    private static let maxRequests = 5

    let cache: LyricsCacheStore
    private let http: any HTTPClient
    private let geniusToken: String
    private let now: @Sendable () -> Date

    init(
        http: any HTTPClient = URLSessionHTTPClient(), cache: LyricsCacheStore = LyricsCacheStore(),
        geniusToken: String = LyricsConfig.geniusAccessToken, now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.http = http
        self.cache = cache
        self.geniusToken = geniusToken
        self.now = now
    }

    func lyrics(for track: TrackInfo, forceRefresh: Bool = false) async -> LyricsOutcome {
        let cached = await cache.load(track.spotifyID)
        if !forceRefresh, let cached, cached.isFresh(now: now()), let result = cached.lyricsResult {
            return .result(result)
        }
        let run = Run(track: track, service: self)
        switch await run.execute() {
        case let .done(result):
            await cache.save(LyricsCacheFile(
                track: track, result: result, glosses: cached?.glosses ?? [:], fetchedAt: now()))
            return .result(result)
        case .offline:
            // A stale "not available" beats an error message when there is no connection.
            if let cached, let result = cached.lyricsResult { return .result(result) }
            return .offline
        case let .failed(message):
            if let cached, let result = cached.lyricsResult, case .available = result { return .result(result) }
            return .failed(message)
        }
    }

    // MARK: One lookup

    private enum Fetched {
        case ok(Data)
        case notFound
        case failed
        case offline
        case exhausted
        case cancelled
    }

    private enum Finish {
        case done(LyricsResult)
        case offline
        case failed(String)
    }

    /// State of one song's lookup: the request budget and what was seen along the way.
    private final class Run {
        let track: TrackInfo
        let service: LyricsService
        let titles: [String]
        let artist: String
        var requestsLeft = LyricsService.maxRequests
        var sawNonKorean = false
        var incomplete = false
        var offline = false
        var cancelled = false
        /// Hits of the Genius lyrics search, reused to look for the translation page.
        var geniusHits: [GeniusHit]?

        init(track: TrackInfo, service: LyricsService) {
            self.track = track
            self.service = service
            titles = TrackQuery.titles(for: track)
            artist = track.primaryArtist
        }

        func fetch(_ spec: HTTPRequestSpec?) async -> Fetched {
            guard let spec else { return .failed }
            guard requestsLeft > 0 else { return .exhausted }
            requestsLeft -= 1
            do {
                let r = try await service.http.sendRetryingServerError(spec)
                if r.isSuccess { return .ok(r.data) }
                return r.status == 404 ? .notFound : .failed
            } catch HTTPError.offline {
                return .offline
            } catch is CancellationError {
                return .cancelled
            } catch {
                return .failed
            }
        }

        /// Lines that pass the Korean check, or `nil` (noting what went wrong).
        func accept(_ lines: [LyricLine]?) -> [LyricLine]? {
            guard let lines else { return nil }
            if KoreanLyricsCheck.isKorean(lines) { return lines }
            sawNonKorean = true
            return nil
        }

        func note(_ f: Fetched) {
            switch f {
            case .failed, .exhausted: incomplete = true
            case .offline: offline = true; incomplete = true
            case .cancelled: cancelled = true; incomplete = true
            case .ok, .notFound: break
            }
        }

        func execute() async -> Finish {
            var found: (lines: [LyricLine], source: String)?
            var instrumental = false

            // 1. LRCLIB /get, with the English title and then the Korean one.
            for title in titles where found == nil && !instrumental && !stop {
                let f = await fetch(LRCLIBParser.getRequest(title: title, artist: artist, album: track.album, durationMs: track.durationMs))
                note(f)
                guard case let .ok(data) = f, let record = LRCLIBParser.parseRecord(data) else { continue }
                if record.instrumental { instrumental = true; break }
                if let lines = accept(LRCLIBParser.lines(from: record)) { found = (lines, "LRCLIB") }
            }
            // 2. LRCLIB /search.
            if found == nil, !instrumental, !stop, let title = titles.first {
                let f = await fetch(LRCLIBParser.searchRequest(title: title, artist: artist))
                note(f)
                if case let .ok(data) = f,
                   let record = LRCLIBParser.bestMatch(LRCLIBParser.parseSearch(data), titles: titles, artist: artist, durationMs: track.durationMs) {
                    if record.instrumental { instrumental = true } else if let lines = accept(LRCLIBParser.lines(from: record)) {
                        found = (lines, "LRCLIB")
                    }
                }
            }
            // 3. Genius.
            if found == nil, !instrumental, !stop, !service.geniusToken.isEmpty {
                found = await geniusLyrics()
            }

            if cancelled { return .failed("Cancelled") }
            if let found {
                let english = await englishLines()
                let doc = LyricsDocument(
                    korean: found.lines, english: english, koreanSource: found.source, englishSource: english == nil ? nil : "Genius")
                return .done(.available(doc))
            }
            if instrumental { return .done(.notAvailable(.instrumental)) }
            if offline { return .offline }
            // A failed request means "unknown", which must not be cached as "not available".
            if incomplete { return .failed("Couldn't reach the lyrics sources. Try again.") }
            return .done(.notAvailable(sawNonKorean ? .notKorean : .notFound))
        }

        private var stop: Bool { cancelled || offline }

        private func geniusLyrics() async -> (lines: [LyricLine], source: String)? {
            for title in titles where !stop {
                let f = await fetch(GeniusParser.searchRequest(query: "\(title) \(artist)", accessToken: service.geniusToken))
                note(f)
                guard case let .ok(data) = f else { continue }
                let hits = GeniusParser.parseSearch(data)
                if geniusHits == nil { geniusHits = hits }
                guard let hit = GeniusParser.lyricsHit(hits, artists: track.artists, titles: titles) else { continue }
                let page = await fetch(GeniusParser.pageRequest(hit.url))
                note(page)
                guard case let .ok(html) = page, let text = String(data: html, encoding: .utf8),
                      let lines = accept(GeniusParser.lyrics(fromHTML: text)) else { continue }
                return (lines, "Genius")
            }
            return nil
        }

        /// English translation lines, or `nil`. Never an error (L-D6).
        private func englishLines() async -> [LyricLine]? {
            guard !service.geniusToken.isEmpty, !stop else { return nil }
            var hit = geniusHits.flatMap { GeniusParser.translationHit($0, artists: track.artists, titles: titles) }
            if hit == nil {
                let query = "\(artist) \(titles[0]) English Translation"
                if case let .ok(data) = await fetch(GeniusParser.searchRequest(query: query, accessToken: service.geniusToken)) {
                    hit = GeniusParser.translationHit(GeniusParser.parseSearch(data), artists: track.artists, titles: titles)
                }
            }
            guard let hit, case let .ok(html) = await fetch(GeniusParser.pageRequest(hit.url)),
                  let text = String(data: html, encoding: .utf8) else { return nil }
            return GeniusParser.lyrics(fromHTML: text)
        }
    }
}
