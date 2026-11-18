import Foundation
import MemoriseCore

struct HTTPResponse: Sendable {
    let status: Int
    let data: Data
    /// Header names lower-cased.
    let headers: [String: String]

    func header(_ name: String) -> String? { headers[name.lowercased()] }
    var isSuccess: Bool { (200..<300).contains(status) }
}

enum HTTPError: Error, Equatable, Sendable {
    /// No connection (airplane mode, no data, connection lost).
    case offline
    case timedOut
    case invalidRequest
    case transport(String)
}

/// Network seam for the Lyrics feature. Production uses `URLSession`; tests and previews can swap it.
protocol HTTPClient: Sendable {
    func send(_ spec: HTTPRequestSpec) async throws -> HTTPResponse
}

extension HTTPClient {
    /// One retry on a 5xx, as PLAN_M6 §4.4 allows. Transport errors are not retried.
    func sendRetryingServerError(_ spec: HTTPRequestSpec) async throws -> HTTPResponse {
        let first = try await send(spec)
        guard (500..<600).contains(first.status) else { return first }
        return try await send(spec)
    }
}

/// `URLSession`-backed client: ephemeral (no cookies, no disk cache), 10 s timeout per request.
struct URLSessionHTTPClient: HTTPClient {
    private let session: URLSession

    init(session: URLSession? = nil) {
        if let session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForRequest = LyricsHTTP.timeout
            config.timeoutIntervalForResource = LyricsHTTP.timeout * 2
            config.waitsForConnectivity = false
            self.session = URLSession(configuration: config)
        }
    }

    func send(_ spec: HTTPRequestSpec) async throws -> HTTPResponse {
        var request = URLRequest(url: spec.url, timeoutInterval: LyricsHTTP.timeout)
        request.httpMethod = spec.method
        request.httpBody = spec.body
        for (k, v) in spec.headers { request.setValue(v, forHTTPHeaderField: k) }
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw HTTPError.invalidRequest }
            var headers: [String: String] = [:]
            for (k, v) in http.allHeaderFields {
                if let k = k as? String, let v = v as? String { headers[k.lowercased()] = v }
            }
            return HTTPResponse(status: http.statusCode, data: data, headers: headers)
        } catch let e as HTTPError {
            throw e
        } catch let e as URLError {
            switch e.code {
            case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed, .internationalRoamingOff,
                 .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed:
                throw HTTPError.offline
            case .timedOut:
                throw HTTPError.timedOut
            case .cancelled:
                throw CancellationError()
            default:
                throw HTTPError.transport(e.localizedDescription)
            }
        }
    }
}

/// Always offline: previews and tests that must never reach the network.
struct OfflineHTTPClient: HTTPClient {
    func send(_ spec: HTTPRequestSpec) async throws -> HTTPResponse { throw HTTPError.offline }
}
