import Foundation

// Type for the lexicon `at-identifier` string format: either a DID or a Handle. Per the AT
// Protocol Identifier spec (https://atproto.com/specs/at-identifier), inputs starting with `did:`
// are validated as DIDs; everything else is validated as a Handle. Wire bytes round-trip via
// `rawValue` byte-for-byte.
public enum AtIdentifier: LexiconStringFormat {
  case did(DID)
  case handle(Handle)

  public var rawValue: String {
    switch self {
    case .did(let d): d.rawValue
    case .handle(let h): h.rawValue
    }
  }

  public init(string: String) throws {
    if string.hasPrefix("did:") {
      self = .did(try DID(string: string))
    } else {
      self = .handle(try Handle(string: string))
    }
  }
}

extension AtIdentifier {
  // Strict per the dispatch rule above. Accepts `String` and `Substring` for both top-level use
  // and as a callable component validator from `ATURI`.
  static func isValid(_ s: some StringProtocol) -> Bool {
    s.hasPrefix("did:") ? DID.isValid(s) : Handle.isValid(s)
  }
}
