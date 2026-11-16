/// Stable identifier of a deck, e.g. `"music.fretboard.notes"`, `"ko.core.1"`.
public struct DeckID: Hashable, Comparable, Codable, Sendable, ExpressibleByStringLiteral, CustomStringConvertible {
    public let raw: String

    public init(_ raw: String) { self.raw = raw }
    public init(stringLiteral value: String) { self.raw = value }

    public init(from decoder: any Decoder) throws {
        raw = try decoder.singleValueContainer().decode(String.self)
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(raw)
    }

    public var description: String { raw }
    public static func < (lhs: DeckID, rhs: DeckID) -> Bool { lhs.raw < rhs.raw }
}

/// Statistics key of a single learnable item; unique across **all** decks.
///
/// Never rename or reuse an `ItemKey` once shipped — stats are joined on it.
public struct ItemKey: Hashable, Comparable, Codable, Sendable, ExpressibleByStringLiteral, CustomStringConvertible {
    public let raw: String

    public init(_ raw: String) { self.raw = raw }
    public init(stringLiteral value: String) { self.raw = value }

    public init(from decoder: any Decoder) throws {
        raw = try decoder.singleValueContainer().decode(String.self)
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(raw)
    }

    public var description: String { raw }
    public static func < (lhs: ItemKey, rhs: ItemKey) -> Bool { lhs.raw < rhs.raw }
}
