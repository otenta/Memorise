import Foundation
import Testing
@testable import MemoriseCore

/// F5 (P1-2) tolerant decoding of persisted config + pinned on-disk shape; §6.1 identifier encoding.
@Suite("Persisted Codable tolerance (F5)")
struct CodableToleranceTests {
    /// Golden fixture in the synthesised `DeckOptions` / `SessionLength` shape (`{"case":{"_0":…}}`).
    static let fretboardGolden = #"""
    {"deckID":"music.fretboard.notes","focus":"strong","length":{"minutes":{"_0":5}},"options":{"fretboard":{"_0":{"accidentalSpelling":"mixed","fretRange":[0,15],"noteSet":"all","strings":[5,6]}}},"retryWrongCards":false}
    """#
    static let fretboardExpected = SessionConfig(
        deckID: "music.fretboard.notes",
        options: .fretboard(FretboardOptions(strings: [5, 6], noteSet: .all, accidentalSpelling: .mixed, fretRange: 0...15)),
        length: .minutes(5), focus: .strong, retryWrongCards: false
    )

    static let vocabGolden = #"""
    {"deckID":"ko.aion2","focus":"normal","length":{"cards":{"_0":20}},"options":{"vocab":{"_0":{"autoPlayAudio":true,"direction":"both","newPerSession":5,"tags":["combat"]}}},"retryWrongCards":true}
    """#
    /// Current encoder output: M2 added `inputMode` / `micTimeoutSeconds` (defaults); the legacy
    /// `vocabGolden` above must still decode to the same value.
    static let vocabCurrentGolden = #"""
    {"deckID":"ko.aion2","focus":"normal","inputMode":"touch","length":{"cards":{"_0":20}},"micTimeoutSeconds":10,"options":{"vocab":{"_0":{"autoPlayAudio":true,"direction":"both","newPerSession":5,"tags":["combat"]}}},"retryWrongCards":true}
    """#
    static let vocabExpected = SessionConfig(
        deckID: "ko.aion2", options: .vocab(VocabOptions(direction: .both, newPerSession: 5, tags: ["combat"]))
    )

    private func decode<T: Decodable>(_ json: String, as: T.Type = SessionConfig.self) throws -> T {
        try JSONDecoder().decode(T.self, from: Data(json.utf8))
    }

    private func encodeSorted(_ value: some Encodable) throws -> String {
        let e = JSONEncoder()
        e.outputFormatting = .sortedKeys
        return String(decoding: try e.encode(value), as: UTF8.self)
    }

    @Test func goldenFixturesDecode() throws {
        #expect(try decode(Self.fretboardGolden) == Self.fretboardExpected)
        #expect(try decode(Self.vocabGolden) == Self.vocabExpected)
    }

    @Test func encodingKeepsThePinnedShape() throws {
        let json = try encodeSorted(Self.vocabExpected)
        #expect(json == Self.vocabCurrentGolden, "on-disk format of SessionConfig changed")
        #expect(try decode(json) == Self.vocabExpected)
        let fret = try encodeSorted(Self.fretboardExpected)
        #expect(fret.contains(#""options":{"fretboard":{"_0":{"#))
        #expect(fret.contains(#""length":{"minutes":{"_0":5}}"#))
        #expect(try decode(fret) == Self.fretboardExpected)
    }

    @Test func unknownKeysAreIgnored() throws {
        let json = Self.fretboardGolden.replacingOccurrences(of: #""focus":"strong""#, with: #""focus":"strong","futureField":[1,2,3]"#)
            .replacingOccurrences(of: #""noteSet":"all""#, with: #""noteSet":"all","capo":3"#)
        #expect(try decode(json) == Self.fretboardExpected)
    }

    @Test func tuningKeyIsHonouredAndUnknownTuningFallsBackToStandard() throws {
        let drop = Self.fretboardGolden.replacingOccurrences(of: #""noteSet":"all""#, with: #""noteSet":"all","tuning":"dropD""#)
        #expect(try decode(drop).options.tuning == .dropD)
        let bad = try decode(#"{"tuning":"sevenString"}"#, as: FretboardOptions.self)
        #expect(bad.tuning == .standard)
    }

    @Test func persistedFormatCheckPasses() {
        #expect(PersistedFormatCheck.run() == [])
    }

    @Test func missingPropertiesFallBackToDefaults() throws {
        let c = try decode(#"{"deckID":"music.fretboard.notes"}"#)
        #expect(c == SessionConfig(deckID: "music.fretboard.notes", options: .fretboard(FretboardOptions())))
        let partial = try decode(#"{"deckID":"ko.core.1","options":{"vocab":{"_0":{"direction":"enToKo"}}}}"#)
        #expect(partial.options == .vocab(VocabOptions(direction: .enToKo)))
        let fret = try decode(#"{"strings":[1]}"#, as: FretboardOptions.self)
        #expect(fret == FretboardOptions(strings: [1]))
    }

    @Test func unknownEnumRawValuesFallBack() throws {
        let fret = try decode(#"{"noteSet":"chromaticPlus","accidentalSpelling":"doubleSharps","fretRange":[0,24]}"#, as: FretboardOptions.self)
        #expect(fret.noteSet == .naturals)
        #expect(fret.accidentalSpelling == .sharps)
        #expect(fret.fretRange == 0...24)
        let vocab = try decode(#"{"direction":"sideways","newPerSession":"ten"}"#, as: VocabOptions.self)
        #expect(vocab == VocabOptions())
        let cfg = try decode(#"{"deckID":"ko.core.1","focus":"extreme","length":{"weeks":{"_0":1}},"retryWrongCards":"yes"}"#)
        #expect(cfg.focus == .normal)
        #expect(cfg.length == .cards(20))
        #expect(cfg.retryWrongCards)
    }

    @Test func invalidFretRangeFallsBack() throws {
        let fret = try decode(#"{"fretRange":[12,0]}"#, as: FretboardOptions.self)
        #expect(fret.fretRange == 0...12)
    }

    @Test func garbageOptionsUseDeckFallback() throws {
        let fret = try decode(#"{"deckID":"music.fretboard.notes","options":"garbage"}"#)
        #expect(fret.options == .fretboard(FretboardOptions()))
        let vocab = try decode(#"{"deckID":"ko.aion2","options":{"piano":{"_0":{}}}}"#)
        #expect(vocab.options == .vocab(VocabOptions()))
        #expect(DeckOptions.fallback(for: FretboardNotesDeck.deckID) == .fretboard(FretboardOptions()))
        #expect(DeckOptions.fallback(for: "ko.core.1") == .vocab(VocabOptions()))
    }

    @Test func deckIDIsRequired() {
        #expect(throws: (any Error).self) { try decode(#"{"focus":"off"}"#) }
    }

    @Test func sessionRecordRoundTripsWithEmbeddedConfig() throws {
        let r = SessionRecord(id: UUID(), deckID: "ko.aion2", startedAt: fixedNow, endedAt: fixedNow.addingTimeInterval(60), status: .completed, config: Self.vocabExpected)
        let back = try JSONDecoder().decode(SessionRecord.self, from: JSONEncoder().encode(r))
        #expect(back == r)
    }

    @Test func identifiersEncodeAsBareStrings() throws {
        #expect(try encodeSorted([ItemKey("fret:s6:A")]) == #"["fret:s6:A"]"#)
        #expect(try encodeSorted([DeckID("ko.core.1")]) == #"["ko.core.1"]"#)
        #expect(try encodeSorted([PitchClass(13)]) == "[1]")
        #expect(try decode(#"["x"]"#, as: [ItemKey].self) == ["x"])
    }

    @Test func persistedEnumRawValuesAreStable() {
        #expect(SessionStatus.inProgress.rawValue == "inProgress")
        #expect(FocusLevel.allCases.map(\.rawValue) == ["off", "normal", "strong"])
        #expect(FretboardOptions.NoteSet.allCases.map(\.rawValue) == ["naturals", "all"])
        #expect(FretboardOptions.AccidentalSpelling.allCases.map(\.rawValue) == ["sharps", "flats", "mixed"])
        #expect(VocabOptions.DirectionOption.allCases.map(\.rawValue) == ["koToEn", "enToKo", "both", "listening", "allThree"])
        #expect(TuningID.allCases.map(\.rawValue) == ["standard", "dropD", "halfDown", "dadgad", "openG"])
        #expect(Subject.allCases.map(\.rawValue) == ["music", "korean"])
    }

    @Test func focusLevelParameters() {
        #expect(FocusLevel.off.gamma == 0 && FocusLevel.off.errorWeight == 0)
        #expect(FocusLevel.normal.gamma == 1.5 && FocusLevel.normal.errorWeight == 3)
        #expect(FocusLevel.strong.gamma == 2.5 && FocusLevel.strong.errorWeight == 5)
        #expect(SessionLength.default == .cards(20))
        #expect(SessionLength.cardPresets == [10, 20, 30, 50])
        #expect(SessionLength.minutePresets == [3, 5, 10])
    }
}
