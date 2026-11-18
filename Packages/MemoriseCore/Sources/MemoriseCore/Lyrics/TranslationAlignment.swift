/// Pairs Korean lyric lines with their English translation, only when it is unambiguous (PLAN_M6 §4.11).
public enum TranslationAlignment {
    public struct Pair: Hashable, Sendable {
        /// Index of the Korean line in `LyricsDocument.korean`.
        public let koreanIndex: Int
        public let ko: String
        public let en: String
    }

    /// Drops section headers and blank lines on both sides. Equal counts → pairs by position; otherwise `nil`.
    /// No guessing.
    public static func pairs(korean: [LyricLine], english: [LyricLine]) -> [Pair]? {
        let ko = korean.enumerated().filter { !$0.element.isSectionHeader && !$0.element.text.isEmpty }
        let en = english.filter { !$0.isSectionHeader && !$0.text.isEmpty }
        guard !ko.isEmpty, ko.count == en.count else { return nil }
        return zip(ko, en).map { Pair(koreanIndex: $0.offset, ko: $0.element.text, en: $1.text) }
    }

    /// English line for the Korean line at `index`, or `nil` when the document has no English or isn't alignable.
    public static func englishLine(forKoreanLineAt index: Int, in document: LyricsDocument) -> String? {
        guard let english = document.english else { return nil }
        return pairs(korean: document.korean, english: english)?.first { $0.koreanIndex == index }?.en
    }
}
