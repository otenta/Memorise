import Foundation

/// A request described as plain data, so core can build requests without networking. The app turns it into a `URLRequest`.
public struct HTTPRequestSpec: Hashable, Sendable {
    public var url: URL
    public var method: String
    public var headers: [String: String]
    public var body: Data?

    public init(url: URL, method: String = "GET", headers: [String: String] = [:], body: Data? = nil) {
        self.url = url
        self.method = method
        self.headers = headers
        self.body = body
    }
}

/// Shared by every lyrics source (PLAN_M6 §3 privacy: no personal data in requests).
public enum LyricsHTTP {
    public static let userAgent = "Memorise/1.0 (personal, non-commercial)"
    public static let timeout: TimeInterval = 10

    /// `base` + query items, percent-encoded. `nil` only when `base` isn't a valid URL.
    static func url(_ base: String, _ items: [(String, String)] = []) -> URL? {
        guard var c = URLComponents(string: base) else { return nil }
        if !items.isEmpty { c.queryItems = items.map { URLQueryItem(name: $0.0, value: $0.1) } }
        return c.url
    }
}
