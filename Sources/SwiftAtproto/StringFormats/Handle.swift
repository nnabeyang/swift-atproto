import Foundation

// Type for the lexicon `handle` string format: a DNS-like atproto handle per the AT Protocol
// Handle spec (https://atproto.com/specs/handle).
//
// Wire-shape validation only: each label is 1–63 byte ASCII alnum / hyphen with no edge hyphen,
// the trailing TLD starts with a letter, the whole string is dot-separated with at least two
// labels, and total length is <= 253 byte. Punycode (`xn--…`) labels pass the same byte test —
// IDN canonicalization is intentionally not performed.
public struct Handle: LexiconStringFormat {
  // The original wire string, kept verbatim.
  public let rawValue: String

  public init(string: String) throws {
    guard Handle.isValid(string) else {
      throw LexiconStringFormatError.invalid(format: "handle", value: string)
    }
    rawValue = string
  }
}

extension Handle {
  // Sentinel returned by handle-verification paths (e.g. `DIDDocument.Verified`) when the handle
  // cannot be confirmed against the DID. Well-formed per `isValid`, so it never fails to
  // construct at runtime.
  public static let invalid: Handle = try! Handle(string: "handle.invalid")
}

extension Handle {
  // Strict per the grammar above. Accepts `String` and `Substring` for both top-level use and
  // as a callable component validator from `ATURI` / `AtIdentifier`.
  static func isValid(_ s: some StringProtocol) -> Bool {
    guard s.utf8.count <= 253 else { return false }
    let labels = s.split(separator: ".", omittingEmptySubsequences: false)
    guard labels.count >= 2 else { return false }
    for (index, label) in labels.enumerated() {
      let u = Array(label.utf8)
      guard (1...63).contains(u.count) else { return false }
      for byte in u where !(isAlphanumeric(byte) || byte == hyphen) { return false }
      guard u.first != hyphen, u.last != hyphen else { return false }
      if index == labels.count - 1, !isAlpha(u[0]) { return false }  // TLD starts with a letter
    }
    return true
  }
}

private let hyphen = UInt8(ascii: "-")
