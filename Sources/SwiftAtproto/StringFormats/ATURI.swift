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
// DID / Handle / NSID / RecordKey / AtIdentifier component validators live in their dedicated
// identifier-type files. Only the JSON Pointer fragment validator remains here.
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
    guard AtIdentifier.isValid(authority) else { return nil }
    if let collection, !NSID.isValid(collection) { return nil }
    if let fragment, !isValidJSONPointer(fragment) { return nil }

    // Strict-only constraints.
    if trailingSlash { return nil }
    if hasQuery { return nil }
    if let rkey, !RecordKey.isValid(rkey) { return nil }

    return Parts(authority: authority, collection: collection, rkey: rkey, fragment: fragment)
  }

  // MARK: - JSON Pointer fragment

  // JSON Pointer fragment: starts with "/", allowed pointer chars, with valid percent-encoding.
  private static func isValidJSONPointer(_ s: Substring) -> Bool {
    let u = Array(s.utf8)
    guard u.first == slash else { return false }
    for byte in u where !(isAlphanumeric(byte) || pointerPunct.contains(byte)) { return false }
    return String(s).removingPercentEncoding != nil
  }
}

// MARK: - ASCII byte helpers

private let slash = UInt8(ascii: "/")

private let uriAllowedPunct = Set(#"._~:@!$&'()*+,;=%/\[]#?-"#.utf8)
private let pointerPunct = Set("._~:@!$&')(*+,;=%[]/-".utf8)

private func isAllowedURIByte(_ b: UInt8) -> Bool { isAlphanumeric(b) || uriAllowedPunct.contains(b) }
