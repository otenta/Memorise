/// Fixed-do solfège variant for B.
public enum SolfegeVariant: String, Codable, Sendable, CaseIterable {
    case si, ti
}

/// How note names are shown.
public enum NoteNaming: String, Codable, Sendable, CaseIterable {
    /// "A"
    case letter
    /// "La"
    case solfege
    /// "A (La)"
    case both
}

/// Display settings that core formatting depends on (mirrors app settings).
public struct MusicDisplaySettings: Hashable, Codable, Sendable {
    public var naming: NoteNaming
    public var solfegeVariant: SolfegeVariant
    public var showStringHint: Bool

    public init(naming: NoteNaming = .both, solfegeVariant: SolfegeVariant = .si, showStringHint: Bool = true) {
        self.naming = naming
        self.solfegeVariant = solfegeVariant
        self.showStringHint = showStringHint
    }

    public static let `default` = MusicDisplaySettings()
}

/// Pure note-name formatting.
public enum NoteFormatter {
    /// Fixed-do syllable for a letter.
    public static func solfege(_ letter: NoteLetter, variant: SolfegeVariant) -> String {
        switch letter {
        case .c: "Do"
        case .d: "Re"
        case .e: "Mi"
        case .f: "Fa"
        case .g: "Sol"
        case .a: "La"
        case .b: variant == .si ? "Si" : "Ti"
        }
    }

    /// Formats a spelling, e.g. `"A (La)"`, `"C♯ (Do♯)"`, `"Si♭"`.
    public static func format(_ spelling: NoteSpelling, naming: NoteNaming, variant: SolfegeVariant = .si) -> String {
        let sym = spelling.accidental.symbol
        switch naming {
        case .letter:
            return spelling.letter.name + sym
        case .solfege:
            return solfege(spelling.letter, variant: variant) + sym
        case .both:
            return "\(spelling.letter.name)\(sym) (\(solfege(spelling.letter, variant: variant))\(sym))"
        }
    }

    /// Formats using display settings.
    public static func format(_ spelling: NoteSpelling, settings: MusicDisplaySettings) -> String {
        format(spelling, naming: settings.naming, variant: settings.solfegeVariant)
    }
}
