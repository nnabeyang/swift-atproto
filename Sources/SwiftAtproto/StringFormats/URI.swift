import Foundation

// Type for the lexicon `uri` string format: a lenient parser that keeps the wire string
// verbatim and exposes best-effort typed accessors for known schemes (`url: URL?` and
// `atUri: ATURI?`).
//
// Scope: atproto lexicon `uri` is "flexible to any URI schema" per RFC 3986
// (https://atproto.com/specs/lexicon). This parser only enforces the wire-level shape:
//   - RFC 3986 §3.1 scheme grammar (ALPHA *( ALPHA / DIGIT / "+" / "-" / "." )) followed by ":"
//   - optional "//"
//   - non-empty body whose first byte is neither "/" nor ASCII whitespace, and whose remaining
//     bytes contain no ASCII whitespace / control characters
//   - total length <= 8 KiB (per spec)
// Non-ASCII bytes in the body are accepted verbatim (per the spec's "any scheme" stance);
// canonicalization is left to the consumer.
//
// `URL` is intentionally NOT used as the conformance: `URL(string:)` silently re-encodes
// wire characters (spaces → `%20`, IDN → punycode, etc.), and even
// `URL(string:encodingInvalidCharacters: false)` is too strict for our lenient wire
// admission (rejects inputs the lexicon `uri` format may carry, e.g. raw non-ASCII bytes)
// while still rejecting `at://did:plc:…` (the DID authority's embedded colon collides with
// port grammar). `URL` is offered as a best-effort derived accessor instead, exposing the
// `encodingInvalidCharacters:` toggle so callers choose between best-effort (silent
// re-encoding) and strict wire-faithful (nil for inputs needing encoding).
public struct URI: LexiconStringFormat {
  // The original wire string, kept verbatim (no normalization).
  public let rawValue: String
  // The URI scheme (before the colon), preserved verbatim (no lowercase canonicalization).
  public let scheme: String
  public let kind: Kind

  public enum Kind: Sendable, Hashable {
    case url
    case aturl
    case other
  }

  public init(string: String) throws {
    guard let parsedScheme = URI.parse(string) else {
      throw LexiconStringFormatError.invalid(format: "uri", value: string)
    }
    rawValue = string
    scheme = parsedScheme
    kind = URI.classify(string)
  }

  // Best-effort `URL` projection. The `encodingInvalidCharacters` parameter is forwarded to
  // `URL(string:encodingInvalidCharacters:)`:
  //   - `true` (default, matching Foundation's historical `URL(string:)` behavior): silently
  //     re-encodes wire characters that need encoding (spaces → `%20`, IDN → punycode, etc.)
  //     and converts the result to a usable URL when possible. `absoluteString` may diverge
  //     from `rawValue`.
  //   - `false`: returns nil for wire forms that would require any re-encoding. When
  //     non-nil, the URL's `absoluteString` matches `rawValue` byte-for-byte (wire-faithful).
  //
  // Returns nil in either mode for inputs `URL` cannot parse — notably any URI whose
  // authority contains a colon followed by non-numeric bytes (port grammar violation, e.g.
  // `at://did:plc:abc` or `at://example.com:notaport/path`). Non-nil does NOT imply the URL
  // is semantically loadable (e.g. `https:///x` parses but has no host).
  public func url(encodingInvalidCharacters: Bool = true) -> URL? {
    URL(string: rawValue, encodingInvalidCharacters: encodingInvalidCharacters)
  }

  // Best-effort AT-URI projection. Non-nil only when the wire string is a valid restricted-form
  // AT URI (scheme=at, authority=DID/handle, …).
  public var atUri: ATURI? { try? ATURI(string: rawValue) }
}

extension URI {
  // `at:` is matched case-sensitively; `AT://` falls through to the URL branch.
  private static func classify(_ s: String) -> Kind {
    if s.hasPrefix("at:") {
      if (try? ATURI(string: s)) != nil { return .aturl }
    }
    if URL(string: s) != nil { return .url }
    return .other
  }

  // 8 KiB per atproto spec.
  private static let maxLength = 8 * 1024

  static func parse(_ input: String) -> String? {
    guard !input.isEmpty, input.utf8.count <= maxLength else { return nil }
    let bytes = Array(input.utf8)
    var i = 0

    // RFC 3986 §3.1: scheme = ALPHA *( ALPHA / DIGIT / "+" / "-" / "." )
    guard i < bytes.count, isSchemeFirst(bytes[i]) else { return nil }
    let schemeStart = i
    i += 1
    while i < bytes.count, isSchemeRest(bytes[i]) { i += 1 }

    // ":"
    guard i < bytes.count, bytes[i] == 0x3A else { return nil }
    let schemeEnd = i
    i += 1

    // optional "//"
    if i + 1 < bytes.count, bytes[i] == 0x2F, bytes[i + 1] == 0x2F {
      i += 2
    }

    // Body: at least 1 byte; first byte must not be whitespace / control. A leading "/" is
    // allowed because RFC 3986 §3 lets `hier-part` be `path-absolute` (`scheme:/path`) or
    // `"//" authority path-abempty` with empty authority + path-abempty (`scheme:///path`).
    guard i < bytes.count else { return nil }
    guard isBodyByte(bytes[i]) else { return nil }
    i += 1

    // Body remainder: no whitespace / control bytes.
    while i < bytes.count {
      guard isBodyByte(bytes[i]) else { return nil }
      i += 1
    }

    // Scheme is pure ASCII by grammar, so direct byte slice is safe.
    return String(bytes: bytes[schemeStart..<schemeEnd], encoding: .ascii)
  }

  // RFC 3986 §3.1: scheme starts with ALPHA (A-Z / a-z).
  private static func isSchemeFirst(_ b: UInt8) -> Bool {
    (0x41...0x5A).contains(b) || (0x61...0x7A).contains(b)
  }

  // RFC 3986 §3.1: subsequent scheme chars are ALPHA / DIGIT / "+" / "-" / ".".
  private static func isSchemeRest(_ b: UInt8) -> Bool {
    isSchemeFirst(b)
      || (0x30...0x39).contains(b)  // DIGIT
      || b == 0x2B  // +
      || b == 0x2D  // -
      || b == 0x2E  // .
  }

  // Body byte: anything that is not an ASCII control character (0x00-0x1F) or space (0x20) or
  // DEL (0x7F). Non-ASCII bytes (>= 0x80) are accepted verbatim; the consumer may percent-encode.
  private static func isBodyByte(_ b: UInt8) -> Bool {
    b > 0x20 && b != 0x7F
  }
}
