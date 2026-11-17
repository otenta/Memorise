import Foundation

/// The user's own note for a vocab entry ("My snippet", PLAN_M5 K4), e.g. a lyric line they want to remember.
/// Stored only on the device and included only in the user's own export. Never bundled.
public struct PersonalSnippet: Hashable, Codable, Sendable {
    /// Longest allowed `text`, in characters.
    public static let maxTextLength = 500

    public let text: String
    /// Free text, e.g. a song or show name.
    public let source: String?
    public let updatedAt: Date

    /// Trims both fields, caps `text` at `maxTextLength`, and turns a blank `source` into `nil`.
    public init(text: String, source: String? = nil, updatedAt: Date) {
        self.text = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.maxTextLength))
        let trimmedSource = source?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.source = (trimmedSource?.isEmpty ?? true) ? nil : trimmedSource
        self.updatedAt = updatedAt
    }

    /// Nothing to keep (an empty save means delete).
    public var isEmpty: Bool { text.isEmpty }

    private enum CodingKeys: String, CodingKey { case text, source, updatedAt }

    /// Tolerant: a missing `text` decodes as empty and `updatedAt` defaults to the distant past.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            text: (try? c.decodeIfPresent(String.self, forKey: .text)) ?? "",
            source: try? c.decodeIfPresent(String.self, forKey: .source),
            updatedAt: (try? c.decodeIfPresent(Date.self, forKey: .updatedAt)) ?? .distantPast
        )
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(text, forKey: .text)
        try c.encodeIfPresent(source, forKey: .source)
        try c.encode(updatedAt, forKey: .updatedAt)
    }
}

/// On-disk file for personal snippets: `{ "schemaVersion": 1, "snippets": { "<entry id>": PersonalSnippet } }`.
public struct PersonalSnippetFile: Codable, Sendable, Hashable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    /// Keyed by `VocabEntry.id`.
    public let snippets: [String: PersonalSnippet]

    public init(snippets: [String: PersonalSnippet]) {
        schemaVersion = Self.currentSchemaVersion
        self.snippets = snippets
    }

    private enum CodingKeys: String, CodingKey { case schemaVersion, snippets }

    /// Tolerant: empty snippets are dropped; one unreadable snippet doesn't lose the others.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = (try? c.decodeIfPresent(Int.self, forKey: .schemaVersion)) ?? Self.currentSchemaVersion
        let raw = (try? c.decodeIfPresent([String: LossySnippet].self, forKey: .snippets)) ?? [:]
        snippets = raw.compactMapValues { $0.value.flatMap { $0.isEmpty ? nil : $0 } }
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(schemaVersion, forKey: .schemaVersion)
        try c.encode(snippets, forKey: .snippets)
    }

    /// Shared JSON encoder settings (dates as ISO 8601, stable key order).
    public static func encoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        e.dateEncodingStrategy = .iso8601
        return e
    }

    public static func decoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}

private struct LossySnippet: Decodable {
    let value: PersonalSnippet?
    init(from decoder: any Decoder) throws { value = try? PersonalSnippet(from: decoder) }
}
