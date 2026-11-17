import Foundation
import Testing
@testable import MemoriseCore

/// PLAN_M4 M4-4 typed answers; R4-2 / R5-1 grading rules (PLAN §17).
@Suite("Typed answer matching (M4-4, R4-2, R5-1)")
struct AnswerMatcherTests {
    private func hangul(_ input: String, _ expected: String, predicate: Bool = false,
                        cls: ConjugationClass = .regular, adjective: Bool = false) -> AnswerVerdict {
        AnswerMatcher.match(input: input, expected: [expected], kind: .hangul, isPredicate: predicate,
                            conjugationClass: cls, isAdjective: adjective).verdict
    }

    private func english(_ input: String, _ expected: String) -> AnswerVerdict {
        AnswerMatcher.match(input: input, expected: [expected], kind: .english).verdict
    }

    // MARK: General

    @Test func blankInputOrNoExpectedIsWrong() {
        #expect(AnswerMatcher.match(input: "  \n", expected: ["가다"], kind: .hangul).verdict == .wrong)
        let none = AnswerMatcher.match(input: "가다", expected: [], kind: .hangul)
        #expect(none.verdict == .wrong)
        #expect(none.closest == "")
    }

    @Test func anyExpectedAnswerMatchesAndExactBeatsClose() {
        let r = AnswerMatcher.match(input: "eat", expected: ["drink", "eat"], kind: .english)
        #expect(r.verdict == .exact)
        #expect(r.closest == "eat")
        // A close match on the first answer is replaced by an exact match on a later one.
        let r2 = AnswerMatcher.match(input: "house", expected: ["houses", "house"], kind: .english)
        #expect(r2.verdict == .exact && r2.closest == "house")
        // Close reports the matching answer, not the first.
        let r3 = AnswerMatcher.match(input: "elephnt", expected: ["dog", "elephant"], kind: .english)
        #expect(r3.verdict == .close && r3.closest == "elephant")
        // Wrong reports the first answer.
        #expect(AnswerMatcher.match(input: "zzz", expected: ["dog", "cat"], kind: .english).closest == "dog")
    }

    @Test func specOverloadForwardsAllFields() {
        let spec = TypedAnswerSpec(expected: ["먹다"], kind: .hangul, exactRequired: true, isPredicate: true)
        #expect(AnswerMatcher.match(input: "먹어요", spec: spec).verdict == .close)
        #expect(!AnswerVerdict.close.isCorrect(exactRequired: spec.exactRequired))
    }

    @Test func verdictGrades() {
        #expect(AnswerVerdict.exact.isCorrect(exactRequired: true))
        #expect(AnswerVerdict.close.isCorrect(exactRequired: false))
        #expect(!AnswerVerdict.close.isCorrect(exactRequired: true))
        #expect(!AnswerVerdict.wrong.isCorrect(exactRequired: false))
    }

    // MARK: Hangul

    @Test func hangulExactIgnoresSpacingPunctuationAndNormalisation() {
        #expect(hangul("재사용 대기시간", "재사용대기시간") == .exact)
        #expect(hangul("안녕하세요!", "안녕하세요") == .exact)
        // Decomposed (NFD) jamo input equals the precomposed word.
        #expect(hangul("학교".decomposedStringWithCanonicalMapping, "학교") == .exact)
    }

    @Test func predicateAffirmativeConjugationsAreClose() {
        #expect(hangul("먹어요", "먹다", predicate: true) == .close)
        #expect(hangul("먹어", "먹다", predicate: true) == .close)
        #expect(hangul("먹었어요", "먹다", predicate: true) == .close)
        #expect(hangul("먹었어", "먹다", predicate: true) == .close)     // polite 요 dropped
        #expect(hangul("공부해요", "공부하다", predicate: true, cls: .ha) == .close)
        #expect(hangul("도와요", "돕다", predicate: true, cls: .b) == .close)
        #expect(hangul("들어요", "듣다", predicate: true, cls: .d) == .close)
        #expect(hangul("몰라요", "모르다", predicate: true, cls: .reu) == .close)
    }

    @Test func predicateNegativeFormsAreWrongR51() {
        #expect(hangul("안 가요", "가다", predicate: true) == .wrong)
        #expect(hangul("몰라요", "알다", predicate: true, cls: .l) == .wrong)
        #expect(hangul("없어요", "있다", predicate: true) == .wrong)
    }

    @Test func predicateStemOrSharedSyllableIsNotClose() {
        #expect(hangul("먹", "먹다", predicate: true) == .wrong)
        #expect(hangul("가방", "가다", predicate: true) == .wrong)
        // Vowel stems: the stem *is* the casual form (가 / 어디 가?), so it is close by design.
        #expect(hangul("가", "가다", predicate: true) == .close)
    }

    @Test func conjugationsOnlyCountForPredicates() {
        #expect(hangul("먹어요", "먹다") == .wrong)
    }

    @Test func adjectivesHaveNoWantToForm() {
        #expect(hangul("먹고 싶어요", "먹다", predicate: true) == .close)
        #expect(hangul("크고 싶어요", "크다", predicate: true, cls: .eu, adjective: true) == .wrong)
    }

    @Test func shortWordsOnlyAcceptABatchimSlip() {
        #expect(hangul("잇다", "있다") == .close)
        #expect(hangul("만이", "많이") == .close)
        #expect(hangul("의자", "의사") == .wrong)      // initial changed → different word
        #expect(hangul("거방", "가방") == .wrong)      // vowel changed
        #expect(hangul("갇갑", "가방") == .wrong)      // two batchim slips
        #expect(hangul("물", "불") == .wrong)          // one syllable: never close
        #expect(hangul("문", "물") == .wrong)
    }

    @Test func longWordsAllowOneJamoEdit() {
        #expect(hangul("대한민구", "대한민국") == .close)  // dropped final
        #expect(hangul("대한먼국", "대한민국") == .close)  // one vowel substitution
        #expect(hangul("대헌먼국", "대한민국") == .wrong)  // two edits
    }

    @Test func batchimSlipHelper() {
        #expect(AnswerMatcher.isBatchimSlip("잇다", "있다"))
        #expect(!AnswerMatcher.isBatchimSlip("있다", "있다"))        // no difference
        #expect(!AnswerMatcher.isBatchimSlip("있", "있다"))          // length differs
        #expect(!AnswerMatcher.isBatchimSlip("a다", "b다"))          // not syllables
    }

    // MARK: English

    @Test func englishNormalisesCaseArticlesAndPunctuation() {
        #expect(english("  The Cat. ", "cat") == .exact)
        #expect(english("to go", "go") == .exact)
        #expect(english("an apple", "apple") == .exact)
        #expect(english("don’t", "don't") == .exact)
        #expect(english("ice   cream", "ice cream") == .exact)
    }

    @Test func englishGlossesSplitAndParentheticalsStrip() {
        #expect(english("bag", "bag (for carrying)") == .exact)
        #expect(english("purse", "bag / purse") == .exact)
        #expect(english("purse", "bag; purse") == .exact)
        #expect(english("for carrying", "bag (for carrying)") == .wrong)
    }

    @Test func englishTypoToleranceIsIndelOnly() {
        #expect(english("hous", "house") == .close)          // 1 drop at 5 letters
        #expect(english("hose", "hose") == .exact)
        #expect(english("hos", "hose") == .wrong)            // < 5 letters: no tolerance
        #expect(english("restaurnt", "restaurant") == .close)
        #expect(english("restarnt", "restaurant") == .close) // 2 drops at ≥ 9
        #expect(english("hoose", "house") == .wrong)         // substitution
        #expect(english("three", "there") == .wrong)         // transposition
        #expect(english("angle", "angel") == .wrong)
        #expect(english("quiet", "quite") == .wrong)
        #expect(english("hose", "house") == .close)          // drop from expected side
        #expect(english("houses", "house") == .close)        // extra letter
    }

    @Test func distanceHelpers() {
        #expect(AnswerMatcher.indelDistance(Array("abc"), Array("")) == 3)
        #expect(AnswerMatcher.indelDistance(Array("ab"), Array("ba")) == 2)
        #expect(AnswerMatcher.editDistance(Array("ab"), Array("ba")) == 1)
        #expect(AnswerMatcher.editDistance(Array(""), Array("abc")) == 3)
        #expect(AnswerMatcher.editDistance(Array("kitten"), Array("sitting")) == 3)
        #expect(AnswerMatcher.stripParentheticals("a (b (c)) d") == "a  d")
    }

    // MARK: Romanization

    @Test func romanizationIgnoresSeparatorsAndRL() {
        let r = { (i: String, e: String) in AnswerMatcher.match(input: i, expected: [e], kind: .romanization).verdict }
        #expect(r("Annyeong-haseyo", "annyeonghaseyo") == .exact)
        #expect(r("sa rang", "sarang") == .exact)
        #expect(r("salang", "sarang") == .exact)
        #expect(r("sarangg", "sarang") == .wrong)
    }

    // MARK: Diff

    @Test func diffFlagsMismatchedInputCharacters() {
        let d = AnswerMatcher.diff("hxuse", against: "house")
        #expect(String(d.map(\.character)) == "hxuse")
        #expect(d.map(\.matches) == [true, false, true, true, true])
        #expect(AnswerMatcher.diff("", against: "x").isEmpty)
        #expect(AnswerMatcher.diff("abc", against: "").allSatisfy { !$0.matches })
    }

    @Test func hangulHelpers() {
        #expect(Hangul.jamo("닭") == ["ㄷ", "ㅏ", "ㄺ"])
        #expect(Hangul.jamo("a") == ["a"])
        #expect(Hangul.compose(initial: 0, medial: 0) == "가")
        #expect(Hangul.finalIndex(of: "밥") == 17)
        #expect(Hangul.finalIndex(of: "가") == 0)
        #expect(Hangul.finalIndex(of: "abc") == nil)
    }
}

/// PLAN_M5 K4: "My snippet" persistence.
@Suite("Personal snippets (M5 K4)")
struct PersonalSnippetTests {
    @Test func initTrimsCapsAndBlanksSource() {
        let s = PersonalSnippet(text: "  hi \n", source: "   ", updatedAt: fixedNow)
        #expect(s.text == "hi")
        #expect(s.source == nil)
        let long = PersonalSnippet(text: String(repeating: "가", count: 600), source: " IU ", updatedAt: fixedNow)
        #expect(long.text.count == PersonalSnippet.maxTextLength)
        #expect(long.source == "IU")
        #expect(PersonalSnippet(text: " ", updatedAt: fixedNow).isEmpty)
    }

    @Test func tolerantSnippetDecoding() throws {
        let d = PersonalSnippetFile.decoder()
        let s = try d.decode(PersonalSnippet.self, from: Data(#"{"source":"x","future":1}"#.utf8))
        #expect(s.text == "" && s.source == "x" && s.updatedAt == .distantPast)
    }

    @Test func fileRoundTripsAndDropsEmptyOrBrokenSnippets() throws {
        let file = PersonalSnippetFile(snippets: [
            "ko.media.0001": PersonalSnippet(text: "line", source: "song", updatedAt: fixedNow),
        ])
        let data = try PersonalSnippetFile.encoder().encode(file)
        let text = String(decoding: data, as: UTF8.self)
        #expect(text.contains(#""schemaVersion" : 1"#))
        #expect(try PersonalSnippetFile.decoder().decode(PersonalSnippetFile.self, from: data) == file)

        let messy = #"""
        {"snippets":{"a":{"text":"keep","updatedAt":"2027-01-15T08:00:00Z"},"b":{"text":"  "},"c":{"text":42},"d":"garbage"}}
        """#
        let back = try PersonalSnippetFile.decoder().decode(PersonalSnippetFile.self, from: Data(messy.utf8))
        #expect(back.schemaVersion == PersonalSnippetFile.currentSchemaVersion)
        #expect(Array(back.snippets.keys) == ["a"])
        #expect(back.snippets["a"]?.updatedAt == fixedNow)
    }

    @Test func garbageFileDecodesEmpty() throws {
        let back = try PersonalSnippetFile.decoder().decode(PersonalSnippetFile.self, from: Data(#"{"snippets":[1,2]}"#.utf8))
        #expect(back.snippets.isEmpty)
    }
}
