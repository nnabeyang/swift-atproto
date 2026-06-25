import Foundation

// A dedicated AT URI type for the lexicon `at-uri` string format. There is no natural Foundation type
// (`URL` rejects the `at://` scheme and normalizes), so this is a self-contained, range-based parser.
//
// Scope: this implements ONLY the *restricted* (Lexicon) AT URI syntax in strict mode, per the
// AT Protocol AT URI spec (https://atproto.com/specs/at-uri-scheme):
//
//   AT-URI     = "at://" AUTHORITY [ "/" COLLECTION [ "/" RKEY ] ] [ "#" FRAGMENT ]
//   AUTHORITY  = HANDLE | DID
//   COLLECTION = NSID
//   RKEY       = RECORD-KEY
//
// This is the form used by lexicon `at-uri` fields and covers essentially all real AT URIs. The
// general AT URI syntax (multi-segment paths, query strings) is intentionally NOT supported. A parse
// mode for the lenient variant (relaxed record key, trailing slash, query) may be added to this same
// type later (`init(string:strict:)` / `typedLenient`); a fully permissive/general parser would be a
// separate addition if a concrete need arises.
//
// The DID/Handle/NSID/record-key validators are kept private here; they may later be promoted to
// dedicated identifier types and shared.
public struct ATURI: LexiconStringFormat {
  // The original wire string, kept verbatim (no normalization).
  public let rawValue: String
  // Required authority: a DID or a handle.
  public let authority: String
  // Optional collection NSID.
  public let collection: String?
  // Optional record key (trailing path segment).
  public let rkey: String?
  // Optional JSON Pointer fragment (without the leading "#").
  public let fragment: String?

  public init(string: String) throws {
    guard let parts = ATURI.parse(string) else {
      throw LexiconStringFormatError.invalid(format: "at-uri", value: string)
    }
    rawValue = string
    authority = String(parts.authority)
    collection = parts.collection.map(String.init)
    rkey = parts.rkey.map(String.init)
    fragment = parts.fragment.map(String.init)
  }
}

extension ATURI {
  private struct Parts {
    var authority: Substring
    var collection: Substring?
    var rkey: Substring?
    var fragment: Substring?
  }

  // Strict restricted-syntax validation per the AT URI spec. Returns nil on any violation.
  private static func parse(_ input: String) -> Parts? {
    guard input.utf8.count <= 8192 else { return nil }
    for byte in input.utf8 where !isAllowedURIByte(byte) { return nil }
    guard input.hasPrefix("at://") else { return nil }

    let end = input.endIndex
    var i = input.index(input.startIndex, offsetBy: 5)

    func isPathDelimiter(_ c: Character) -> Bool { c == "/" || c == "?" || c == "#" }
    func scanSegment() -> Substring {
      let start = i
      while i < end, !isPathDelimiter(input[i]) { i = input.index(after: i) }
      return input[start..<i]
    }
    func atSegmentBoundary() -> Bool { i >= end || input[i] == "?" || input[i] == "#" }

    let authority = scanSegment()
    if authority.isEmpty { return nil }

    var collection: Substring?
    var rkey: Substring?
    var trailingSlash = false

    if i < end, input[i] == "/" {
      i = input.index(after: i)
      if atSegmentBoundary() {
        trailingSlash = true
      } else {
        collection = scanSegment()
        if i < end, input[i] == "/" {
          i = input.index(after: i)
          if atSegmentBoundary() {
            trailingSlash = true
          } else {
            rkey = scanSegment()
            if i < end, input[i] == "/" {
              i = input.index(after: i)
              if atSegmentBoundary() {
                trailingSlash = true
              } else {
                return nil  // more than two path segments
              }
            }
          }
        }
      }
    }

    var hasQuery = false
    if i < end, input[i] == "?" {
      hasQuery = true
      i = input.index(after: i)
      while i < end, input[i] != "#" { i = input.index(after: i) }
    }

    var fragment: Substring?
    if i < end, input[i] == "#" {
      i = input.index(after: i)
      fragment = input[i..<end]
      i = end
    }

    guard i == end else { return nil }

    // Component validation (applies in both strict and lenient).
    guard isValidAtIdentifier(authority) else { return nil }
    if let collection, !isValidNSID(collection) { return nil }
    if let fragment, !isValidJSONPointer(fragment) { return nil }

    // Strict-only constraints.
    if trailingSlash { return nil }
    if hasQuery { return nil }
    if let rkey, !isValidRecordKey(rkey) { return nil }

    return Parts(authority: authority, collection: collection, rkey: rkey, fragment: fragment)
  }

  // MARK: - Component validators (DID / Handle / NSID / record key / JSON pointer)

  private static func isValidAtIdentifier(_ s: Substring) -> Bool {
    s.hasPrefix("did:") ? isValidDID(s) : isValidHandle(s)
  }

  // /^did:[a-z]+:[a-zA-Z0-9._:%-]*[a-zA-Z0-9._-]$/ with length <= 2048
  private static func isValidDID(_ s: Substring) -> Bool {
    let u = Array(s.utf8)
    guard u.count <= 2048, u.starts(with: Array("did:".utf8)) else { return false }
    var i = 4
    let methodStart = i
    while i < u.count, isLowerAlpha(u[i]) { i += 1 }
    guard i > methodStart, i < u.count, u[i] == colon else { return false }
    i += 1
    guard i < u.count else { return false }  // identifier needs >= 1 char
    while i < u.count {
      guard isDIDIdentifierByte(u[i]) else { return false }
      i += 1
    }
    let last = u[u.count - 1]
    return last != colon && last != percent
  }

  // /^([a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?\.)+[a-zA-Z]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?$/, <= 253
  private static func isValidHandle(_ s: Substring) -> Bool {
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

  // NSID rules: <= 317, [a-zA-Z0-9.-], >= 3 segments (1..63, no edge hyphen),
  // first segment not leading-digit, last segment letters/digits only with no leading digit.
  private static func isValidNSID(_ s: Substring) -> Bool {
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

  // /^[a-zA-Z0-9_~.:-]{1,512}$/, excluding "." and ".."
  private static func isValidRecordKey(_ s: Substring) -> Bool {
    let u = Array(s.utf8)
    guard (1...512).contains(u.count) else { return false }
    for byte in u where !(isAlphanumeric(byte) || recordKeyPunct.contains(byte)) { return false }
    return s != "." && s != ".."
  }

  // JSON Pointer fragment: starts with "/", allowed pointer chars, with valid percent-encoding.
  private static func isValidJSONPointer(_ s: Substring) -> Bool {
    let u = Array(s.utf8)
    guard u.first == slash else { return false }
    for byte in u where !(isAlphanumeric(byte) || pointerPunct.contains(byte)) { return false }
    return String(s).removingPercentEncoding != nil
  }
}

// MARK: - ASCII byte helpers

private let colon = UInt8(ascii: ":")
private let percent = UInt8(ascii: "%")
private let hyphen = UInt8(ascii: "-")
private let dot = UInt8(ascii: ".")
private let slash = UInt8(ascii: "/")

private let uriAllowedPunct = Set(#"._~:@!$&'()*+,;=%/\[]#?-"#.utf8)
private let recordKeyPunct = Set("_~.:-".utf8)
private let pointerPunct = Set("._~:@!$&')(*+,;=%[]/-".utf8)

private func isDigit(_ b: UInt8) -> Bool { (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(b) }
private func isLowerAlpha(_ b: UInt8) -> Bool { (UInt8(ascii: "a")...UInt8(ascii: "z")).contains(b) }
private func isUpperAlpha(_ b: UInt8) -> Bool { (UInt8(ascii: "A")...UInt8(ascii: "Z")).contains(b) }
private func isAlpha(_ b: UInt8) -> Bool { isLowerAlpha(b) || isUpperAlpha(b) }
private func isAlphanumeric(_ b: UInt8) -> Bool { isAlpha(b) || isDigit(b) }
private func isAllowedURIByte(_ b: UInt8) -> Bool { isAlphanumeric(b) || uriAllowedPunct.contains(b) }
private func isDIDIdentifierByte(_ b: UInt8) -> Bool {
  isAlphanumeric(b) || b == dot || b == UInt8(ascii: "_") || b == colon || b == percent || b == hyphen
}
