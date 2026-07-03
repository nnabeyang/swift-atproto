import Foundation

// Type for the lexicon `did` string format: Decentralized Identifier per W3C DID spec
// (https://www.w3.org/TR/did-core/) with atproto restrictions per the AT Protocol DID spec
// (https://atproto.com/specs/did).
//
// Wire-shape validation only: ASCII grammar `^did:[a-z]+:[a-zA-Z0-9._:%-]*[a-zA-Z0-9._-]$`,
// total length <= 2048 byte. No `%xx` decoding (verbatim wire preservation). No semantic
// resolution (registered-method resolvers live elsewhere — e.g. `ATProtoCrypto`).
public struct DID: LexiconStringFormat {
  // The original wire string, kept verbatim.
  public let rawValue: String

  public init(string: String) throws {
    guard DID.isValid(string) else {
      throw LexiconStringFormatError.invalid(format: "did", value: string)
    }
    rawValue = string
  }

  // The DID method (the lowercase ASCII segment between the first two colons). For `did:plc:abc`
  // this is `"plc"`; for `did:web:example.com` this is `"web"`. Always non-empty since `rawValue`
  // was admitted by the parser.
  public var method: String {
    let afterPrefix = rawValue.dropFirst(4)  // drop "did:"
    let end = afterPrefix.firstIndex(of: ":") ?? afterPrefix.endIndex
    return String(afterPrefix[..<end])
  }
}

extension DID {
  // An open, extensible tag for the DID method. Use `switch` with `case .plc` / `case .web` /
  // `default` for dispatch; unknown methods survive as `KnownMethod(rawValue:)` values so
  // constructing a DID with a future or unregistered method never fails and never gets silently
  // downgraded. `knownMethod.rawValue == method` always.
  public struct KnownMethod: RawRepresentable, Hashable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public static let plc = Self(rawValue: "plc")
    public static let web = Self(rawValue: "web")
  }

  public var knownMethod: KnownMethod { KnownMethod(rawValue: method) }
}

extension DID {
  // Strict per the grammar above. Accepts `String` and `Substring` so it can serve both as the
  // top-level entry point and as a callable component validator from `ATURI` / `AtIdentifier`.
  static func isValid(_ s: some StringProtocol) -> Bool {
    let u = Array(s.utf8)
    guard u.count <= 2048, u.starts(with: didPrefix) else { return false }
    var i = 4
    let methodStart = i
    while i < u.count, isLowerAlpha(u[i]) { i += 1 }
    guard i > methodStart, i < u.count, u[i] == colon else { return false }
    i += 1
    guard i < u.count else { return false }  // identifier needs >= 1 char
    while i < u.count {
      guard DID.isDIDIdentifierByte(u[i]) else { return false }
      i += 1
    }
    let last = u[u.count - 1]
    return last != colon && last != percent
  }

  private static func isDIDIdentifierByte(_ b: UInt8) -> Bool {
    isAlphanumeric(b) || b == dot || b == underscore || b == colon || b == percent || b == hyphen
  }
}

private let didPrefix = Array("did:".utf8)
private let colon = UInt8(ascii: ":")
private let percent = UInt8(ascii: "%")
private let dot = UInt8(ascii: ".")
private let hyphen = UInt8(ascii: "-")
private let underscore = UInt8(ascii: "_")
