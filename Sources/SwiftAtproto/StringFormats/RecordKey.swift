import Foundation

// Type for the lexicon `record-key` string format: the opaque trailing segment of an AT URI per
// the AT Protocol Record Key spec (https://atproto.com/specs/record-key).
//
// Strict mode (the default `init(string:)`): 1–512 byte ASCII alnum / `_~.:-`, excluding the
// special forbidden values `"."` and `".."`. A lenient mode is also available via
// `init(string:strict: false)`; see that initializer for the relaxed grammar and the resulting
// type-invariant trade-off.
public struct RecordKey: LexiconStringFormat {
  // The original wire string, kept verbatim.
  public let rawValue: String

  public init(string: String) throws {
    guard RecordKey.isValid(string) else {
      throw LexiconStringFormatError.invalid(format: "record-key", value: string)
    }
    rawValue = string
  }

  // Opt-in lenient parsing. Accepts wire strings that violate the strict record-key spec
  // (`.` / `..` / over 512 byte / chars outside `[a-zA-Z0-9_~.:-]`) as long as the value is
  // non-empty and contains no `/`, `?`, or `#`. Caller takes responsibility: a lenient instance
  // can hold values the strict spec rejects, so type invariants weaken when this overload is
  // used explicitly.
  public init(string: String, strict: Bool) throws {
    let valid = strict ? RecordKey.isValid(string) : RecordKey.isValidLenient(string)
    guard valid else {
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

  // Lenient: only the structural constraint imposed by AT URI path syntax (non-empty + no
  // `/`/`?`/`#`). Length and char set restrictions plus the `.` / `..` exclusion are dropped.
  static func isValidLenient(_ s: some StringProtocol) -> Bool {
    let u = Array(s.utf8)
    guard !u.isEmpty else { return false }
    for byte in u where pathDelimiterByte(byte) { return false }
    return true
  }
}

private let recordKeyPunct = Set("_~.:-".utf8)

private func pathDelimiterByte(_ b: UInt8) -> Bool {
  b == UInt8(ascii: "/") || b == UInt8(ascii: "?") || b == UInt8(ascii: "#")
}
