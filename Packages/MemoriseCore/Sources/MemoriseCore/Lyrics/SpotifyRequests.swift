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
        api("/playlists/\(id)/items", [("limit", String(limit)), ("offset", String(offset))], token: token)
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
        var r = api("/tracks/\(id)", token: token)
        if let language { r?.headers["Accept-Language"] = language }
        return r
    }

    /// `PUT /me/player/play` with `{"uris":["spotify:track:<id>"]}`.
    public static func play(trackID: String, token: String) -> HTTPRequestSpec? {
        var r = api("/me/player/play", token: token)
        r?.method = "PUT"
        r?.headers["Content-Type"] = "application/json"
        r?.body = Data(#"{"uris":["spotify:track:\#(trackID)"]}"#.utf8)
        return r
    }

    /// `spotify:track:<id>`, opened with `UIApplication.open` when there is no active device.
    public static func trackURI(_ id: String) -> URL? { URL(string: "spotify:track:\(id)") }

    private static func api(_ path: String, _ items: [(String, String)] = [], token: String) -> HTTPRequestSpec? {
        LyricsHTTP.url(apiBase + path, items).map {
            HTTPRequestSpec(url: $0, headers: [
                "Authorization": "Bearer \(token)", "Accept": "application/json", "User-Agent": LyricsHTTP.userAgent,
            ])
        }
    }
}
