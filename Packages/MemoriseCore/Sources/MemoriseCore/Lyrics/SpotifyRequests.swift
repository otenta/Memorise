import Foundation

/// PKCE helpers. Randomness is injected; hashing (SHA-256) happens in the app with CryptoKit.
public enum SpotifyPKCE {
    private static let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")

    /// 64 random URL-safe characters (RFC 7636 allows 43–128).
    public static func verifier(using rng: inout some RandomNumberGenerator) -> String {
        random(64, using: &rng)
    }

    /// Anti-forgery `state`, checked when the redirect comes back.
    public static func state(using rng: inout some RandomNumberGenerator) -> String {
        random(24, using: &rng)
    }

    /// base64url without padding, for the `code_challenge` (`base64URL(SHA256(verifier))`).
    public static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func random(_ count: Int, using rng: inout some RandomNumberGenerator) -> String {
        String((0..<count).map { _ in alphabet[Int.random(in: 0..<alphabet.count, using: &rng)] })
    }
}

/// Builds every Spotify URL and body, and reads the sign-in redirect (PLAN_M6 §4.9). Pure.
public enum SpotifyRequests {
    public static let redirectScheme = "memorise-spotify"
    public static let redirectURI = "memorise-spotify://callback"
    public static let scopes = [
        "user-read-currently-playing", "user-read-playback-state", "user-modify-playback-state",
        "user-read-recently-played", "playlist-read-private", "playlist-read-collaborative", "user-library-read",
    ]
    static let apiBase = "https://api.spotify.com/v1"
    static let tokenURL = "https://accounts.spotify.com/api/token"

    // MARK: Sign-in

    public static func authorizeURL(clientID: String, codeChallenge: String, state: String) -> URL? {
        LyricsHTTP.url("https://accounts.spotify.com/authorize", [
            ("client_id", clientID),
            ("response_type", "code"),
            ("redirect_uri", redirectURI),
            ("scope", scopes.joined(separator: " ")),
            ("state", state),
            ("code_challenge_method", "S256"),
            ("code_challenge", codeChallenge),
        ])
    }

    public enum CallbackError: Error, Equatable, Sendable {
        /// The user cancelled, or Spotify returned an error.
        case denied(String)
        case stateMismatch
        case missingCode
    }

    /// The authorisation `code` from the redirect URL, after checking `state`.
    public static func authorizationCode(from url: URL, expectedState: String) -> Result<String, CallbackError> {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }
        if let error = value("error") { return .failure(.denied(error)) }
        guard value("state") == expectedState else { return .failure(.stateMismatch) }
        guard let code = value("code"), !code.isEmpty else { return .failure(.missingCode) }
        return .success(code)
    }

    public static func tokenExchange(clientID: String, code: String, codeVerifier: String) -> HTTPRequestSpec? {
        tokenRequest([
            ("grant_type", "authorization_code"), ("code", code), ("redirect_uri", redirectURI),
            ("client_id", clientID), ("code_verifier", codeVerifier),
        ])
    }

    public static func tokenRefresh(clientID: String, refreshToken: String) -> HTTPRequestSpec? {
        tokenRequest([("grant_type", "refresh_token"), ("refresh_token", refreshToken), ("client_id", clientID)])
    }

    private static func tokenRequest(_ fields: [(String, String)]) -> HTTPRequestSpec? {
        guard let url = URL(string: tokenURL) else { return nil }
        var form = URLComponents()
        form.queryItems = fields.map { URLQueryItem(name: $0.0, value: $0.1) }
        // `+` is a literal in a query but a space in a form body, so encode it explicitly.
        let body = (form.percentEncodedQuery ?? "").replacingOccurrences(of: "+", with: "%2B")
        return HTTPRequestSpec(
            url: url, method: "POST",
            headers: ["Content-Type": "application/x-www-form-urlencoded", "User-Agent": LyricsHTTP.userAgent],
            body: Data(body.utf8))
    }

    // MARK: Web API

    public static func me(token: String) -> HTTPRequestSpec? { api("/me", token: token) }

    public static func currentlyPlaying(token: String) -> HTTPRequestSpec? { api("/me/player/currently-playing", token: token) }

    public static func recentlyPlayed(token: String, limit: Int = 50) -> HTTPRequestSpec? {
        api("/me/player/recently-played", [("limit", String(limit))], token: token)
    }

    public static func playlists(token: String, limit: Int = 50, offset: Int = 0) -> HTTPRequestSpec? {
        api("/me/playlists", [("limit", String(limit)), ("offset", String(offset))], token: token)
    }

    /// `/playlists/{id}/items` (`/tracks` was removed in 2026).
    public static func playlistItems(id: String, token: String, limit: Int = 100, offset: Int = 0) -> HTTPRequestSpec? {
        guard isValidID(id) else { return nil }
        return api("/playlists/\(id)/items", [("limit", String(limit)), ("offset", String(offset))], token: token)
    }

    public static func savedTracks(token: String, limit: Int = 50, offset: Int = 0) -> HTTPRequestSpec? {
        api("/me/tracks", [("limit", String(limit)), ("offset", String(offset))], token: token)
    }

    /// `limit` is capped at 10 by Spotify (2026).
    public static func search(query: String, token: String, limit: Int = 10) -> HTTPRequestSpec? {
        api("/search", [("q", query), ("type", "track"), ("limit", String(min(limit, 10)))], token: token)
    }

    /// `language` becomes `Accept-Language` (e.g. "ko-KR") so Spotify localises the names.
    public static func track(id: String, token: String, language: String? = nil) -> HTTPRequestSpec? {
        guard isValidID(id) else { return nil }
        var r = api("/tracks/\(id)", token: token)
        if let language { r?.headers["Accept-Language"] = language }
        return r
    }

    /// `PUT /me/player/play`, plus `?device_id=` when given. The body is `{"uris":[…]}` for `.none`, else
    /// `{"context_uri":…,"offset":{"uri":…}}`, so next and previous follow the playlist or Liked.
    public static func play(
        trackID: String, context: PlayContext = .none, deviceID: String? = nil, token: String
    ) -> HTTPRequestSpec? {
        guard isValidID(trackID), validDevice(deviceID) else { return nil }
        let track = "spotify:track:\(trackID)"
        let body: String
        if let uri = context.uri {
            body = #"{"context_uri":"\#(uri)","offset":{"uri":"\#(track)"}}"#
        } else if context == .none {
            body = #"{"uris":["\#(track)"]}"#
        } else {
            return nil // a context whose ids are invalid
        }
        return player("/me/player/play", method: "PUT", query: deviceQuery(deviceID), body: Data(body.utf8), token: token)
    }

    /// `PUT /me/player/play` with no body: resumes what is paused.
    public static func resume(deviceID: String? = nil, token: String) -> HTTPRequestSpec? {
        guard validDevice(deviceID) else { return nil }
        return player("/me/player/play", method: "PUT", query: deviceQuery(deviceID), body: nil, token: token)
    }

    public static func pause(token: String) -> HTTPRequestSpec? {
        player("/me/player/pause", method: "PUT", query: [], body: nil, token: token)
    }

    public static func next(token: String) -> HTTPRequestSpec? {
        player("/me/player/next", method: "POST", query: [], body: nil, token: token)
    }

    public static func previous(token: String) -> HTTPRequestSpec? {
        player("/me/player/previous", method: "POST", query: [], body: nil, token: token)
    }

    public static func devices(token: String) -> HTTPRequestSpec? { api("/me/player/devices", token: token) }

    /// `PUT /me/player` moves playback to `deviceID`.
    public static func transfer(deviceID: String, play: Bool, token: String) -> HTTPRequestSpec? {
        guard isValidID(deviceID) else { return nil }
        let body = #"{"device_ids":["\#(deviceID)"],"play":\#(play ? "true" : "false")}"#
        return player("/me/player", method: "PUT", query: [], body: Data(body.utf8), token: token)
    }

    /// A player request. Every `PUT`/`POST` carries `Content-Length`, which Spotify needs even with no body.
    private static func player(
        _ path: String, method: String, query: [(String, String)], body: Data?, token: String
    ) -> HTTPRequestSpec? {
        var r = api(path, query, token: token)
        r?.method = method
        if let body {
            r?.headers["Content-Type"] = "application/json"
            r?.body = body
        }
        r?.headers["Content-Length"] = String(body?.count ?? 0)
        return r
    }

    private static func deviceQuery(_ id: String?) -> [(String, String)] { id.map { [("device_id", $0)] } ?? [] }

    private static func validDevice(_ id: String?) -> Bool { id.map(isValidID) ?? true }

    /// Spotify ids are base-62. Anything else (empty, `../me`, `?x=`) must never reach a path or a body.
    public static func isValidID(_ id: String) -> Bool {
        !id.isEmpty && id.unicodeScalars.allSatisfy { $0.isASCII && CharacterSet.alphanumerics.contains($0) }
    }

    private static func api(_ path: String, _ items: [(String, String)] = [], token: String) -> HTTPRequestSpec? {
        LyricsHTTP.url(apiBase + path, items).map {
            HTTPRequestSpec(url: $0, headers: [
                "Authorization": "Bearer \(token)", "Accept": "application/json", "User-Agent": LyricsHTTP.userAgent,
            ])
        }
    }
}
