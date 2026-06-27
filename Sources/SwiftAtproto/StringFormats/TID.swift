import Foundation

// Type for the lexicon `tid` string format: AT Protocol Timestamp Identifier per the AT Protocol
// TID spec (https://atproto.com/specs/tid).
//
// Wire-shape validation only: a 13-character base32-sortable token. The first character is from
// `[234567abcdefghij]` (the high bit of the encoded timestamp is always zero in the foreseeable
// future, restricting the leading character to the lower 16 of the 32-char alphabet). The
// remaining 12 characters are from the full base32-sortable alphabet
// `[234567abcdefghijklmnopqrstuvwxyz]`.
public struct TID: LexiconStringFormat {
  // The original wire string, kept verbatim.
  public let rawValue: String

  public init(string: String) throws {
    guard TID.isValid(string) else {
      throw LexiconStringFormatError.invalid(format: "tid", value: string)
    }
    rawValue = string
  }
}

extension TID {
  // Strict per the grammar above. Accepts `String` and `Substring`.
  static func isValid(_ s: some StringProtocol) -> Bool {
    let u = Array(s.utf8)
    guard u.count == 13 else { return false }
    guard tidFirstChars.contains(u[0]) else { return false }
    for i in 1..<13 where !tidRestChars.contains(u[i]) { return false }
    return true
  }
}

// `[234567abcdefghij]` — first character of a TID (high bit of the timestamp is zero).
private let tidFirstChars: Set<UInt8> = Set("234567abcdefghij".utf8)
// `[234567abcdefghijklmnopqrstuvwxyz]` — full base32-sortable alphabet for subsequent chars.
private let tidRestChars: Set<UInt8> = Set("234567abcdefghijklmnopqrstuvwxyz".utf8)
