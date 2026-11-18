import Foundation

/// How long to wait before asking Spotify what is playing again (PLAN_R10 LA4). Pure.
public enum NowPlayingPoll {
    /// What the last request found.
    public enum Last: Sendable, Equatable {
        /// Something is playing; `remainingMs` is the time until it ends, when known.
        case playing(remainingMs: Int?)
        case pausedOrNothing
        case failed
        case rateLimited(retryAfter: Int?)
    }

    /// Seconds to wait. A song that ends in 4 s is checked again at about 5 s.
    public static func delaySeconds(after last: Last) -> Double {
        switch last {
        case let .playing(remainingMs):
            guard let remainingMs else { return LyricsConstants.nowPlayingPollSeconds }
            let wait = Double(remainingMs) / 1000 + 1
            return min(max(wait, LyricsConstants.nowPlayingMinPollSeconds), LyricsConstants.nowPlayingPollSeconds)
        case .pausedOrNothing:
            return LyricsConstants.nowPlayingPollSeconds
        case .failed:
            return LyricsConstants.nowPlayingErrorPollSeconds
        case let .rateLimited(retryAfter):
            return max(Double(retryAfter ?? 60), LyricsConstants.nowPlayingErrorPollSeconds)
        }
    }
}
