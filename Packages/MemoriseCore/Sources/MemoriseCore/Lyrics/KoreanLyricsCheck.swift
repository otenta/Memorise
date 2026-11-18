/// Decides whether fetched lyrics are Korean (PLAN_M6 §4.3). Based on the lyrics, not on Spotify's genre.
public enum KoreanLyricsCheck {
    /// Hangul syllables ÷ (Hangul syllables + Latin letters), ignoring section headers. 0 when there is neither.
    public static func hangulShare(_ lines: [LyricLine]) -> Double {
        let (hangul, latin) = counts(lines)
        let total = hangul + latin
        return total == 0 ? 0 : Double(hangul) / Double(total)
    }

    /// Korean when the share reaches `minHangulShare` and there are at least `minHangulSyllables` syllables.
    public static func isKorean(_ lines: [LyricLine]) -> Bool {
        let (hangul, latin) = counts(lines)
        guard hangul >= LyricsConstants.minHangulSyllables else { return false }
        return Double(hangul) / Double(hangul + latin) >= LyricsConstants.minHangulShare
    }

    private static func counts(_ lines: [LyricLine]) -> (hangul: Int, latin: Int) {
        var hangul = 0
        var latin = 0
        for line in lines where !line.isSectionHeader {
            for s in line.text.unicodeScalars {
                if Hangul.isSyllable(s) {
                    hangul += 1
                } else if isLatinLetter(s) {
                    latin += 1
                }
            }
        }
        return (hangul, latin)
    }

    private static func isLatinLetter(_ s: Unicode.Scalar) -> Bool {
        switch s.value {
        case 0x41...0x5A, 0x61...0x7A: true
        case 0xC0...0x24F: s.value != 0xD7 && s.value != 0xF7
        default: false
        }
    }
}
