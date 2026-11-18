import Foundation

/// One song hit from the Genius search API.
public struct GeniusHit: Hashable, Sendable {
    public var title: String
    public var artist: String
    public var url: URL

    public init(title: String, artist: String, url: URL) {
        self.title = title
        self.artist = artist
        self.url = url
    }
}

/// Genius search, page parsing and hit selection (PLAN_M6 §4.4, §4.5). Pure string processing.
public enum GeniusParser {
    /// The account that publishes fan English translations.
    public static let translationArtist = "Genius English Translations"
    private static let excludedArtists = ["genius english translations", "genius romanizations"]

    // MARK: Requests

    /// `GET /search?q=` with the client access token.
    public static func searchRequest(query: String, accessToken: String) -> HTTPRequestSpec? {
        LyricsHTTP.url("https://api.genius.com/search", [("q", query)]).map {
            HTTPRequestSpec(url: $0, headers: [
                "User-Agent": LyricsHTTP.userAgent, "Accept": "application/json", "Authorization": "Bearer \(accessToken)",
            ])
        }
    }

    /// The lyrics page itself.
    public static func pageRequest(_ url: URL) -> HTTPRequestSpec {
        HTTPRequestSpec(url: url, headers: ["User-Agent": LyricsHTTP.userAgent, "Accept": "text/html"])
    }

    // MARK: Search response

    private struct SearchResponse: Decodable {
        struct Wrapper: Decodable {
            var hits: [Lossy]?
        }
        struct Lossy: Decodable {
            let hit: GeniusHit?
            private struct Raw: Decodable {
                struct Result: Decodable {
                    struct Artist: Decodable { var name: String? }
                    var url: String?
                    var title: String?
                    var primaryArtist: Artist?
                    enum CodingKeys: String, CodingKey { case url, title, primaryArtist = "primary_artist" }
                }
                var result: Result?
                var type: String?
            }
            init(from decoder: any Decoder) throws {
                let raw = try? Raw(from: decoder)
                if let r = raw?.result, let title = r.title, let artist = r.primaryArtist?.name,
                   let s = r.url, let url = URL(string: s), raw?.type == nil || raw?.type == "song" {
                    hit = GeniusHit(title: title, artist: artist, url: url)
                } else {
                    hit = nil
                }
            }
        }
        var response: Wrapper?
    }

    /// Song hits in the order Genius ranked them. Anything that doesn't decode is skipped.
    public static func parseSearch(_ data: Data) -> [GeniusHit] {
        ((try? JSONDecoder().decode(SearchResponse.self, from: data))?.response?.hits ?? []).compactMap(\.hit)
    }

    // MARK: Hit selection

    /// First hit that is not a translation/romanisation page, whose artist matches one of the track's artists
    /// **and** whose title matches one of `titles` (another song by the same artist must never be shown).
    public static func lyricsHit(_ hits: [GeniusHit], artists: [String], titles: [String]) -> GeniusHit? {
        hits.first { hit in
            !excludedArtists.contains(hit.artist.lowercased())
                && artists.contains { TrackQuery.sameArtist($0, hit.artist) }
                && TrackQuery.titleMatches(hit.title, any: titles)
        }
    }

    /// First English-translation page: primary artist is "Genius English Translations" and the normalised title
    /// contains both the artist and one of the song titles.
    public static func translationHit(_ hits: [GeniusHit], artists: [String], titles: [String]) -> GeniusHit? {
        let titleKeys = titles.map { TrackQuery.key($0) }.filter { !$0.isEmpty }
        return hits.first { hit in
            guard hit.artist.lowercased() == translationArtist.lowercased() else { return false }
            let k = TrackQuery.key(hit.title)
            return artists.contains { TrackQuery.containsWords(hit.title, name: $0) } && titleKeys.contains { k.contains($0) }
        }
    }

    // MARK: Page

    /// Lyrics from a Genius song page: the inner HTML of every `data-lyrics-container="true"` div, in order.
    /// `<br>` becomes a newline, other tags are dropped but keep their text, entities are decoded and
    /// elements marked `data-exclude-from-selection="true"` are removed. `nil` when the page has no
    /// container (Genius changed its layout) or the result has no text.
    public static func lyrics(fromHTML html: String) -> [LyricLine]? {
        let containers = innerHTML(ofElementsWith: "data-lyrics-container=\"true\"", in: html)
        guard !containers.isEmpty else {
            #if DEBUG
            print("Genius layout changed: no data-lyrics-container found")
            #endif
            return nil
        }
        let raw = containers.map { text(fromLyricsHTML: $0) }.joined(separator: "\n")
        let lines = LyricsText.lines(from: raw)
        return lines.contains { !$0.text.isEmpty } ? lines : nil
    }

    static func text(fromLyricsHTML html: String) -> String {
        var s = removeElements(withAttribute: "data-exclude-from-selection=\"true\"", in: html)
        s = s.replacingOccurrences(of: #"<br\s*/?>"#, with: "\n", options: [.regularExpression, .caseInsensitive])
        s = s.replacingOccurrences(of: "<[^>]*>", with: "", options: .regularExpression)
        return LyricsText.decodeHTMLEntities(s)
    }

    // MARK: Minimal element scanner

    /// Range of the element whose opening tag contains `marker`: from `<` to just after its matching close tag.
    private static func elementRange(containing marker: String, in html: String, from start: String.Index) -> (outer: Range<String.Index>, inner: Range<String.Index>)? {
        guard let m = html.range(of: marker, range: start..<html.endIndex),
              let open = html[..<m.lowerBound].lastIndex(of: "<"),
              let openEnd = html[m.upperBound...].firstIndex(of: ">")
        else { return nil }
        let nameChars = html[html.index(after: open)...].prefix { $0.isLetter || $0.isNumber }
        let name = String(nameChars).lowercased()
        guard !name.isEmpty else { return nil }
        let innerStart = html.index(after: openEnd)
        var depth = 1
        var i = innerStart
        while let lt = html[i...].firstIndex(of: "<") {
            let after = html.index(after: lt)
            let tail = html[after...]
            if tail.hasPrefix("/" + name) {
                guard let gt = tail.firstIndex(of: ">") else { return nil }
                depth -= 1
                if depth == 0 { return (open..<html.index(after: gt), innerStart..<lt) }
                i = html.index(after: gt)
            } else {
                if tail.hasPrefix(name), let c = tail.dropFirst(name.count).first, " >/\n\t".contains(c) { depth += 1 }
                i = after
            }
        }
        return nil
    }

    private static func innerHTML(ofElementsWith marker: String, in html: String) -> [String] {
        var out: [String] = []
        var from = html.startIndex
        while let r = elementRange(containing: marker, in: html, from: from) {
            out.append(String(html[r.inner]))
            from = r.outer.upperBound
        }
        return out
    }

    private static func removeElements(withAttribute marker: String, in html: String) -> String {
        var result = html
        while let r = elementRange(containing: marker, in: result, from: result.startIndex) {
            result.removeSubrange(r.outer)
        }
        return result
    }
}
