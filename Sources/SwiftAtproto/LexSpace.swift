import Foundation

/// The key type a Lexicon declaration recommends for the keys under it: `any`,
/// `nsid`, `tid`, or a `literal:` value.
///
/// Space type declarations carry one as ``LexSpace/key``. Record declarations
/// use the same vocabulary, so this type is not specific to spaces.
///
/// Unknown values round-trip through ``rawValue`` rather than failing to
/// decode, so a declaration written against a newer Lexicon still reads.
public struct LexRecordKeyType: RawRepresentable, Codable, Hashable, Sendable {
  public let rawValue: String

  public init(rawValue: String) {
    self.rawValue = rawValue
  }

  public init(from decoder: Decoder) throws {
    self.rawValue = try decoder.singleValueContainer().decode(String.self)
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(rawValue)
  }

  /// Any key syntactically valid as a record key.
  public static let any = Self(rawValue: "any")
  /// An NSID.
  public static let nsid = Self(rawValue: "nsid")
  /// A TID.
  public static let tid = Self(rawValue: "tid")

  /// A key fixed to one literal value, encoded as `literal:<value>`.
  ///
  /// The value is not validated here; read it back with ``literalValue``.
  public static func literal(_ value: String) -> Self {
    Self(rawValue: "\(literalPrefix)\(value)")
  }

  /// The value behind a `literal:` key type, or `nil` for every other key type.
  ///
  /// An empty value (a bare `"literal:"`) reads back as `nil`, matching the
  /// AT Protocol requirement that a literal key name a non-empty value.
  public var literalValue: String? {
    guard rawValue.hasPrefix(Self.literalPrefix) else { return nil }
    let value = rawValue.dropFirst(Self.literalPrefix.count)
    return value.isEmpty ? nil : String(value)
  }

  private static let literalPrefix = "literal:"
}

/// A space type declaration, generated from a Lexicon `space` definition.
///
/// A space type NSID resolves to one of these. ``name`` is what an OAuth
/// consent screen shows when an application asks for access to spaces of this
/// type, and ``collections`` is the record collections a client should expect
/// to find inside such a space.
public protocol LexSpace {
  /// The NSID of the declaring Lexicon.
  static var id: String { get }
  /// The key type recommended for space keys of this type.
  static var key: LexRecordKeyType { get }
  /// A human-readable name for the space type, shown to users on consent
  /// screens. 1–64 characters.
  static var name: String { get }
  /// Localized ``name`` values by language code, or `nil` when the declaration
  /// gives none.
  static var nameLang: [String: String]? { get }
  /// The collections clients should expect in a space of this type.
  ///
  /// Advisory only: any collection may be written to any space, and the
  /// protocol does not constrain writes to this list. Empty when the
  /// declaration lists none.
  static var collections: [FormatString<NSID>] { get }
  /// A description of the space type for developers, or `nil` when the
  /// declaration gives none. Not shown to users.
  static var description: String? { get }
}
