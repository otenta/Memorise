import Foundation
import os

/// Performance signposts (PLAN_R11 PA3). On in Release; read them in Instruments → os_signpost, category `perf`.
///
/// Names: `session.reveal`, `session.revealVisible`, `session.nextPrompt`, `speech.speak`, `speech.stop`,
/// `audio.activate`, `headline.layout` (event), `gloss.lookupBuild`, `catalog.assemble`, `home.load`.
enum Perf {
    static let signposter = OSSignposter(
        subsystem: Bundle.main.bundleIdentifier ?? "Memorise", category: "perf")

    /// Times a synchronous block.
    @discardableResult
    static func interval<T>(_ name: StaticString, _ body: () throws -> T) rethrows -> T {
        let state = signposter.beginInterval(name)
        defer { signposter.endInterval(name, state) }
        return try body()
    }

    /// Times an asynchronous block.
    @discardableResult
    static func interval<T>(_ name: StaticString, _ body: () async throws -> T) async rethrows -> T {
        let state = signposter.beginInterval(name)
        defer { signposter.endInterval(name, state) }
        return try await body()
    }

    /// Starts an interval that ends elsewhere (`end(_:_:)`), e.g. when a view appears.
    static func begin(_ name: StaticString) -> OSSignpostIntervalState {
        signposter.beginInterval(name)
    }

    static func end(_ name: StaticString, _ state: OSSignpostIntervalState) {
        signposter.endInterval(name, state)
    }

    static func event(_ name: StaticString) {
        signposter.emitEvent(name)
    }
}
