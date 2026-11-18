import AuthenticationServices
import CryptoKit
import Foundation
import MemoriseCore
import UIKit

enum SpotifyAuthError: Error, Equatable {
    case notConfigured
    case notSignedIn
    /// The user closed the sign-in sheet.
    case cancelled
    /// Spotify refused the refresh token (app removed in account settings, or token revoked).
    case rejected
    case offline
    case failed(String)
}

/// `RandomNumberGenerator` wrapper so the generator can be injected.
struct AnyRNG: RandomNumberGenerator {
    var base: any RandomNumberGenerator
    mutating func next() -> UInt64 { base.next() }
}

/// Authorization Code + PKCE through `ASWebAuthenticationSession` (PLAN_M6 §4.9).
/// The access token lives in memory, the refresh token in the Keychain.
@MainActor
final class SpotifyAuth: NSObject, ASWebAuthenticationPresentationContextProviding {
    private static let refreshKey = "spotify.refreshToken"
    /// Refresh this long before the access token expires.
    private static let refreshLeeway: TimeInterval = 60

    let clientID: String
    private let http: any HTTPClient
    private let secrets: any SecretStore
    private let now: @Sendable () -> Date
    private var rng: AnyRNG
    private var accessToken: String?
    private var expiry = Date.distantPast
    private var refreshTask: Task<String, any Error>?
    private var session: ASWebAuthenticationSession?

    init(
        clientID: String, http: any HTTPClient, secrets: any SecretStore,
        rng: any RandomNumberGenerator = SystemRandomNumberGenerator(),
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.clientID = clientID
        self.http = http
        self.secrets = secrets
        self.rng = AnyRNG(base: rng)
        self.now = now
    }

    var isConfigured: Bool { !clientID.isEmpty }
    var hasStoredSession: Bool { secrets.read(Self.refreshKey) != nil }

    // MARK: Sign in / out

    func signIn() async throws {
        guard isConfigured else { throw SpotifyAuthError.notConfigured }
        let verifier = SpotifyPKCE.verifier(using: &rng)
        let challenge = SpotifyPKCE.base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
        let state = SpotifyPKCE.state(using: &rng)
        guard let url = SpotifyRequests.authorizeURL(clientID: clientID, codeChallenge: challenge, state: state) else {
            throw SpotifyAuthError.failed("Couldn't build the sign-in address")
        }
        let callback = try await webAuthentication(url)
        switch SpotifyRequests.authorizationCode(from: callback, expectedState: state) {
        case let .success(code):
            let token = try await tokenCall(SpotifyRequests.tokenExchange(clientID: clientID, code: code, codeVerifier: verifier))
            apply(token)
        case let .failure(error):
            if case .denied = error { throw SpotifyAuthError.cancelled }
            throw SpotifyAuthError.failed("Sign-in was not completed")
        }
    }

    /// Forgets the session: memory and Keychain.
    func signOut() {
        accessToken = nil
        expiry = .distantPast
        refreshTask?.cancel()
        refreshTask = nil
        secrets.delete(Self.refreshKey)
    }

    // MARK: Tokens

    /// A token valid for at least a minute, refreshing when needed. Concurrent callers share one refresh.
    func validAccessToken() async throws -> String {
        if let accessToken, now() < expiry.addingTimeInterval(-Self.refreshLeeway) { return accessToken }
        return try await refresh()
    }

    /// After a 401: drop the cached token and refresh.
    func refreshAfterUnauthorized() async throws -> String {
        accessToken = nil
        expiry = .distantPast
        return try await refresh()
    }

    private func refresh() async throws -> String {
        if let refreshTask { return try await refreshTask.value }
        let task = Task { try await self.performRefresh() }
        refreshTask = task
        defer { refreshTask = nil }
        return try await task.value
    }

    private func performRefresh() async throws -> String {
        guard isConfigured else { throw SpotifyAuthError.notConfigured }
        guard let refreshToken = secrets.read(Self.refreshKey) else { throw SpotifyAuthError.notSignedIn }
        do {
            let token = try await tokenCall(SpotifyRequests.tokenRefresh(clientID: clientID, refreshToken: refreshToken))
            apply(token)
            return token.accessToken
        } catch SpotifyAuthError.rejected {
            signOut()
            throw SpotifyAuthError.rejected
        }
    }

    private func apply(_ token: SpotifyToken) {
        accessToken = token.accessToken
        expiry = now().addingTimeInterval(TimeInterval(token.expiresIn))
        if let refresh = token.refreshToken { secrets.write(refresh, for: Self.refreshKey) }
    }

    private func tokenCall(_ spec: HTTPRequestSpec?) async throws -> SpotifyToken {
        guard let spec else { throw SpotifyAuthError.failed("Couldn't build the token request") }
        let response: HTTPResponse
        do {
            response = try await http.send(spec)
        } catch HTTPError.offline {
            throw SpotifyAuthError.offline
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw SpotifyAuthError.failed("Couldn't reach Spotify")
        }
        if response.isSuccess, let token = SpotifyDecoder.token(response.data) { return token }
        // 400 invalid_grant / 401: the grant is gone. Anything else (5xx, rate limit) may pass.
        if response.status == 400 || response.status == 401 { throw SpotifyAuthError.rejected }
        throw SpotifyAuthError.failed("Spotify answered \(response.status)")
    }

    // MARK: Web sign-in sheet

    private func webAuthentication(_ url: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: url, callback: .customScheme(SpotifyRequests.redirectScheme)
            ) { callbackURL, error in
                if let callbackURL {
                    continuation.resume(returning: callbackURL)
                } else if let e = error as? ASWebAuthenticationSessionError, e.code == .canceledLogin {
                    continuation.resume(throwing: SpotifyAuthError.cancelled)
                } else {
                    continuation.resume(throwing: SpotifyAuthError.failed("Sign-in failed"))
                }
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            self.session = session
            if !session.start() {
                continuation.resume(throwing: SpotifyAuthError.failed("Couldn't open the sign-in sheet"))
            }
        }
    }

    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            let windows = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows)
            return windows.first(where: \.isKeyWindow) ?? windows.first ?? ASPresentationAnchor()
        }
    }
}
