import Foundation

/// Credentials injected through `Base.xcconfig` / the gitignored `Secrets.xcconfig` into Info.plist (PLAN_M6 L0).
/// Never log or print these.
enum LyricsConfig {
    static var spotifyClientID: String { value("SpotifyClientID") }
    static var geniusAccessToken: String { value("GeniusAccessToken") }

    /// Empty when the key is missing, blank, or still an unexpanded `$(VAR)` placeholder.
    private static func value(_ key: String) -> String {
        let raw = (Bundle.main.object(forInfoDictionaryKey: key) as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return raw.hasPrefix("$(") ? "" : raw
    }
}
