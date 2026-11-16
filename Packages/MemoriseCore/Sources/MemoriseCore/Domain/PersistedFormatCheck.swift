import Foundation

/// Startup guard (DEBUG) that pins the persisted JSON shape of `SessionConfig`,
/// `DeckOptions` and `SessionLength`. Not a test target: it runs at app launch.
public enum PersistedFormatCheck {
    /// Captured on 2026-11-16 from the M1 build (synthesised coding), with set fields sorted.
    static let fixtures: [(json: String, expected: SessionConfig)] = [
        (
            #"{"deckID":"music.fretboard.notes","focus":"strong","length":{"minutes":{"_0":5}},"options":{"fretboard":{"_0":{"accidentalSpelling":"mixed","fretRange":[0,15],"noteSet":"all","strings":[1,6]}}},"retryWrongCards":false}"#,
            SessionConfig(
                deckID: FretboardNotesDeck.deckID,
                options: .fretboard(FretboardOptions(strings: [1, 6], noteSet: .all, accidentalSpelling: .mixed, fretRange: 0...15)),
                length: .minutes(5), focus: .strong, retryWrongCards: false
            )
        ),
        (
            #"{"deckID":"ko.aion2","focus":"normal","length":{"cards":{"_0":30}},"options":{"vocab":{"_0":{"autoPlayAudio":true,"direction":"both","newPerSession":5,"tags":["combat"]}}},"retryWrongCards":true}"#,
            SessionConfig(
                deckID: "ko.aion2",
                options: .vocab(VocabOptions(direction: .both, newPerSession: 5, tags: ["combat"])),
                length: .cards(30)
            )
        ),
    ]

    /// Returns human-readable errors (empty = format intact).
    public static func run() -> [String] {
        let decoder = JSONDecoder()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        var errors: [String] = []
        for (i, f) in fixtures.enumerated() {
            do {
                let decoded = try decoder.decode(SessionConfig.self, from: Data(f.json.utf8))
                if decoded != f.expected { errors.append("fixture \(i): decoded value differs") }
                if !decoded.recoveredFields.isEmpty { errors.append("fixture \(i): recovered \(decoded.recoveredFields.sorted())") }
                let reencoded = String(decoding: try encoder.encode(decoded), as: UTF8.self)
                if reencoded != f.json { errors.append("fixture \(i): re-encoded JSON differs:\n\(reencoded)") }
            } catch {
                errors.append("fixture \(i): \(error)")
            }
        }
        return errors
    }
}
