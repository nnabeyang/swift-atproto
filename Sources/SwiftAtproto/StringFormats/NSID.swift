import Foundation

// Type for the lexicon `nsid` string format: AT Protocol Namespaced Identifier per the AT Protocol
// NSID spec (https://atproto.com/specs/nsid).
//
// Wire-shape validation only: a reverse-DNS authority followed by a name segment, with at least
// three dot-separated segments. Each segment is 1–63 byte ASCII alnum / hyphen with no edge
// hyphen; the first segment cannot start with a digit; the name (last segment) is alnum-only and
// cannot start with a digit. Total length <= 317 byte.
public struct NSID: LexiconStringFormat {
  // The original wire string, kept verbatim.
  public let rawValue: String

  public init(string: String) throws {
    guard NSID.isValid(string) else {
      throw LexiconStringFormatError.invalid(format: "nsid", value: string)
    }
    rawValue = string
  }

  // The reverse-DNS authority portion: all segments except the last one, re-ordered into a
  // forward domain. For `com.example.foo` this is `"example.com"`; for `org.4chan.lex.getThing`
  // it is `"lex.4chan.org"`.
  public var authority: String {
    rawValue.split(separator: ".").dropLast().reversed().joined(separator: ".")
  }

  // The name segment (last dot-separated component). For `com.example.foo` this is `"foo"`.
  public var name: String {
    String(rawValue.split(separator: ".").last ?? "")
  }
}

extension NSID {
  // Strict per the grammar above. Accepts `String` and `Substring` for both top-level use and
  // as a callable component validator from `ATURI`.
  static func isValid(_ s: some StringProtocol) -> Bool {
    let all = Array(s.utf8)
    guard all.count <= 317 else { return false }
    for byte in all where !(isAlphanumeric(byte) || byte == dot || byte == hyphen) { return false }
    let segments = s.split(separator: ".", omittingEmptySubsequences: false)
    guard segments.count >= 3 else { return false }
    for segment in segments {
      let u = Array(segment.utf8)
      guard (1...63).contains(u.count) else { return false }
      guard u.first != hyphen, u.last != hyphen else { return false }
    }
    if isDigit(Array(segments[0].utf8)[0]) { return false }
    let name = Array(segments[segments.count - 1].utf8)
    return !isDigit(name[0]) && !name.contains(hyphen)
  }
}

private let dot = UInt8(ascii: ".")
private let hyphen = UInt8(ascii: "-")
