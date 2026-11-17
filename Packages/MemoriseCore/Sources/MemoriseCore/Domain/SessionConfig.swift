/// How long a session lasts.
///
/// **Persisted format — frozen.** Wire shape: `{"cards":{"_0":20}}` / `{"minutes":{"_0":5}}`.
/// Do not rename cases or change payload types without a legacy decode path and an update to
/// `PersistedFormatCheck`.
public enum SessionLength: Hashable, Codable, Sendable {
    /// Ends after this many counted (non-retry) cards are graded.
    case cards(Int)
    /// Ends when this many minutes of active time have elapsed, after the current card is graded.
    case minutes(Int)

    public static let cardPresets = [10, 20, 30, 50]
    public static let minutePresets = [3, 5, 10]
    public static let `default` = SessionLength.cards(20)

    private enum CodingKeys: String, CodingKey { case cards, minutes }
    private enum PayloadKeys: String, CodingKey { case _0 }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard c.allKeys.count == 1, let key = c.allKeys.first else {
            throw DecodingError.dataCorrupted(.init(codingPath: c.codingPath, debugDescription: "SessionLength needs exactly one case key"))
        }
        let n = try c.nestedContainer(keyedBy: PayloadKeys.self, forKey: key).decode(Int.self, forKey: ._0)
        switch key {
        case .cards: self = .cards(n)
        case .minutes: self = .minutes(n)
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        let (key, n): (CodingKeys, Int) = switch self {
        case let .cards(n): (.cards, n)
        case let .minutes(n): (.minutes, n)
        }
        var p = c.nestedContainer(keyedBy: PayloadKeys.self, forKey: key)
        try p.encode(n, forKey: ._0)
    }
}

/// How strongly the scheduler biases towards slow / wrong cards.
public enum FocusLevel: String, Codable, Sendable, CaseIterable {
    case off, normal, strong

    /// Exponent applied to the slowness ratio.
    public var gamma: Double {
        switch self {
        case .off: 0
        case .normal: 1.5
        case .strong: 2.5
        }
    }

    /// Multiplier applied to the error EWMA.
    public var errorWeight: Double {
        switch self {
        case .off: 0
        case .normal: 3
        case .strong: 5
        }
    }
}

/// How the user answers prompts. Raw values are persisted — never change them.
public enum InputMode: String, Codable, Sendable, CaseIterable {
    /// OK → reveal → self-grade.
    case touch
    /// Play the answer; pitch detection grades correct answers automatically.
    case microphone
    /// Tap one of 2–4 options; graded automatically.
    case choice
    /// Type the answer; graded automatically with a manual override.
    case typed

    /// Whether the response time updates the time EWMA. Typing speed isn't recall speed.
    public var countsTime: Bool { self != .typed }

    public var title: String {
        switch self {
        case .touch: "Touch"
        case .microphone: "Play"
        case .choice: "Choice"
        case .typed: "Type"
        }
    }
}

/// Everything needed to run (and later describe) a session.
public struct SessionConfig: Codable, Hashable, Sendable {
    public var deckID: DeckID
    public var options: DeckOptions
    public var length: SessionLength
    public var focus: FocusLevel
    public var retryWrongCards: Bool
    public var inputMode: InputMode
    /// Microphone mode: seconds before the card reveals for manual grading.
    public var micTimeoutSeconds: Int
    /// Fields that were present on disk but couldn't be decoded and fell back to defaults.
    /// Never encoded; excluded from equality.
    public private(set) var recoveredFields: Set<String> = []

    public init(
        deckID: DeckID,
        options: DeckOptions,
        length: SessionLength = .default,
        focus: FocusLevel = .normal,
        retryWrongCards: Bool = true,
        inputMode: InputMode = .touch,
        micTimeoutSeconds: Int = 10
    ) {
        self.deckID = deckID
        self.options = options
        self.length = length
        self.focus = focus
        self.retryWrongCards = retryWrongCards
        self.inputMode = inputMode
        self.micTimeoutSeconds = micTimeoutSeconds
    }

    public static let micTimeoutPresets = [5, 10, 20]

    private enum CodingKeys: String, CodingKey {
        case deckID, options, length, focus, retryWrongCards, inputMode, micTimeoutSeconds
    }

    /// Tolerant decoding: only `deckID` is required; missing or unknown values fall back to defaults.
    /// A key that is present but undecodable is recorded in `recoveredFields`.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        deckID = try c.decode(DeckID.self, forKey: .deckID)
        var recovered = Set<String>()
        func value<T: Decodable>(_ type: T.Type, _ key: CodingKeys, _ fallback: @autoclosure () -> T) -> T {
            guard c.contains(key) else { return fallback() }
            if let v = try? c.decode(T.self, forKey: key) { return v }
            recovered.insert(key.stringValue)
            return fallback()
        }
        options = value(DeckOptions.self, .options, DeckOptions.fallback(for: deckID))
        length = value(SessionLength.self, .length, .default)
        focus = value(FocusLevel.self, .focus, .normal)
        retryWrongCards = value(Bool.self, .retryWrongCards, true)
        inputMode = value(InputMode.self, .inputMode, .touch)
        micTimeoutSeconds = value(Int.self, .micTimeoutSeconds, 10)
        recoveredFields = recovered
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(deckID, forKey: .deckID)
        try c.encode(options, forKey: .options)
        try c.encode(length, forKey: .length)
        try c.encode(focus, forKey: .focus)
        try c.encode(retryWrongCards, forKey: .retryWrongCards)
        try c.encode(inputMode, forKey: .inputMode)
        try c.encode(micTimeoutSeconds, forKey: .micTimeoutSeconds)
    }

    public static func == (lhs: SessionConfig, rhs: SessionConfig) -> Bool {
        lhs.deckID == rhs.deckID && lhs.options == rhs.options && lhs.length == rhs.length
            && lhs.focus == rhs.focus && lhs.retryWrongCards == rhs.retryWrongCards
            && lhs.inputMode == rhs.inputMode && lhs.micTimeoutSeconds == rhs.micTimeoutSeconds
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(deckID)
        hasher.combine(options)
        hasher.combine(length)
        hasher.combine(focus)
        hasher.combine(retryWrongCards)
        hasher.combine(inputMode)
        hasher.combine(micTimeoutSeconds)
    }

    /// Default configuration for a deck.
    public static func `default`(for deck: any Deck) -> SessionConfig {
        SessionConfig(deckID: deck.id, options: deck.defaultOptions)
    }
}
