/// Decides whether fetched lyrics are Korean (PLAN_M6 §4.3). Based on the lyrics, not on Spotify's genre.
public enum KoreanLyricsCheck {
    /// Hangul syllables ÷ (Hangul syllables + Latin letters), ignoring section headers. 0 when there is neither.
    public static func hangulShare(_ lines: [LyricLine]) -> Double {
        let c = counts(lines)
        let (hangul, latin) = (c.hangul, c.latin)
        let total = hangul + latin
        return total == 0 ? 0 : Double(hangul) / Double(total)
    }

    /// Korean when there are at least `minHangulSyllables` syllables on at least `minHangulLines` lines
    /// (PLAN_R10 P-3). There is no share threshold: half-English K-pop still counts.
    public static func isKorean(_ lines: [LyricLine]) -> Bool {
        let c = counts(lines)
        return c.hangul >= LyricsConstants.minHangulSyllables && c.hangulLines >= LyricsConstants.minHangulLines
    }

    private static func counts(_ lines: [LyricLine]) -> (hangul: Int, latin: Int, hangulLines: Int) {
        var hangul = 0
        var latin = 0
        var hangulLines = 0
        for line in lines where !line.isSectionHeader {
            var lineHangul = 0
            for s in line.text.unicodeScalars {
                if Hangul.isSyllable(s) {
                    lineHangul += 1
                } else if isLatinLetter(s) {
                    latin += 1
                }
            }
            hangul += lineHangul
            if lineHangul > 0 { hangulLines += 1 }
        }
        return (hangul, latin, hangulLines)
    }

    private static func isLatinLetter(_ s: Unicode.Scalar) -> Bool {
        switch s.value {
        case 0x41...0x5A, 0x61...0x7A: true
        case 0xC0...0x24F: s.value != 0xD7 && s.value != 0xF7
        default: false
        }
    }
}
