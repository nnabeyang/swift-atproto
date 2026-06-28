import Foundation

// Type for the lexicon `record-key` string format: the opaque trailing segment of an AT URI per
// the AT Protocol Record Key spec (https://atproto.com/specs/record-key).
//
// Wire-shape validation only: 1–512 byte ASCII alnum / `_~.:-`, excluding the special forbidden
// values `"."` and `".."`.
public struct RecordKey: LexiconStringFormat {
  // The original wire string, kept verbatim.
  public let rawValue: String

  public init(string: String) throws {
    guard RecordKey.isValid(string) else {
      throw LexiconStringFormatError.invalid(format: "record-key", value: string)
    }
    rawValue = string
  }
}

extension RecordKey {
  // Strict per the grammar above. Accepts `String` and `Substring` for both top-level use and
  // as a callable component validator from `ATURI`.
  static func isValid(_ s: some StringProtocol) -> Bool {
    let u = Array(s.utf8)
    guard (1...512).contains(u.count) else { return false }
    for byte in u where !(isAlphanumeric(byte) || recordKeyPunct.contains(byte)) { return false }
    return s != "." && s != ".."
  }
}

private let recordKeyPunct = Set("_~.:-".utf8)
