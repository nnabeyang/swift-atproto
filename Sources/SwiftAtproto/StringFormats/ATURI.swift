import Foundation

/// A dedicated AT URI type for the lexicon `at-uri` string format. There is no natural Foundation type
/// (`URL` rejects the `at://` scheme and normalizes), so this is a self-contained, range-based parser.
///
/// Scope: this implements the *restricted* (Lexicon) AT URI syntax in strict mode, per the
/// AT Protocol AT URI spec (https://atproto.com/specs/at-uri-scheme):
///
///   AT-URI     = "at://" AUTHORITY [ "/" COLLECTION [ "/" RKEY ] ] [ "#" FRAGMENT ]
///   AUTHORITY  = HANDLE | DID
///   COLLECTION = NSID
///   RKEY       = RECORD-KEY
///
/// plus the permissioned-data form, which carries a fixed `space` marker below the authority:
///
///   SPACE-URI  = "at://" DID "/space/" SPACE-TYPE "/" SKEY [ "/" DID "/" COLLECTION "/" RKEY ]
///                [ "#" FRAGMENT ]
///   SPACE-TYPE = NSID
///   SKEY       = RECORD-KEY
///
/// The record triple is all-or-nothing: a space URI either names a space or a record within one.
/// ``isSpace`` discriminates the two forms, and ``collection`` / ``rkey`` / ``authorDid`` name the
/// record either way, so a caller reading a record out of an `at-uri` field does not need to know
/// which form it holds.
///
/// The general AT URI syntax (arbitrary multi-segment paths, query strings) is still NOT supported.
/// A parse mode for the lenient variant (relaxed record key, trailing slash, query) is available
/// through `init(string:strict:)` / `typedLenient`; a fully permissive parser would be a separate
/// addition if a concrete need arises.
///
/// DID / Handle / NSID / RecordKey / AtIdentifier component validators live in their dedicated
/// identifier-type files. Only the JSON Pointer fragment validator remains here.
public struct ATURI: LexiconStringFormat {
  /// The original wire string, kept verbatim (no normalization).
  public let rawValue: String
  /// Required authority: a DID or a handle, dispatched via `AtIdentifier`. Always a DID on a
  /// space URI.
  public let authority: AtIdentifier
  /// Optional collection NSID. On a space URI this is the record's collection, not the `space`
  /// marker, and it is nil when the URI names the space itself.
  public let collection: NSID?
  /// Optional record key (trailing path segment). Nil when the URI names no record.
  public let rkey: RecordKey?
  /// Optional JSON Pointer fragment (without the leading "#").
  public let fragment: String?
  /// Whether this URI addresses permissioned space data.
  public let isSpace: Bool
  /// The authority that owns the space. Nil on a public URI.
  public let spaceDid: DID?
  /// The NSID naming the space type. Nil on a public URI.
  public let spaceType: NSID?
  /// The space key identifying this space within its type. Nil on a public URI.
  public let skey: RecordKey?
  /// The account whose record this is: the fifth segment on a space URI, or the authority on a
  /// public URI when that authority is a DID. Nil when the URI names no record, and nil on a
  /// public URI whose authority is a handle.
  public let authorDid: DID?
  /// The space this URI belongs to, whether it names the space itself or a record within it.
  /// Nil on a public URI.
  public let spaceRef: SpaceRef?

  public init(string: String) throws {
    try self.init(string: string, strict: true)
  }

  public init(string: String, strict: Bool) throws {
    guard let parts = ATURI.parse(string, strict: strict) else {
      throw LexiconStringFormatError.invalid(format: "at-uri", value: string)
    }
    rawValue = string
    // `ATURI.parse` runs each component through its identifier-type validator
    // (`AtIdentifier.isValid` / `DID.isValid` / `NSID.isValid` / `RecordKey.isValid`) before
    // returning, so the typed inits below cannot throw in practice — the force-tries document
    // that invariant.
    authority = try! AtIdentifier(string: String(parts.authority))
    collection = parts.collection.map { try! NSID(string: String($0)) }
    rkey = parts.rkey.map { try! RecordKey(string: String($0), strict: strict) }
    fragment = parts.fragment.map(String.init)
    isSpace = parts.isSpace
    spaceDid = parts.isSpace ? try! DID(string: String(parts.authority)) : nil
    spaceType = parts.spaceType.map { try! NSID(string: String($0)) }
    skey = parts.skey.map { try! RecordKey(string: String($0), strict: strict) }
    if let author = parts.author {
      authorDid = try! DID(string: String(author))
    } else if !parts.isSpace, case .did(let did) = authority {
      authorDid = did
    } else {
      authorDid = nil
    }
    // Composed from the already-validated segments rather than re-parsing `rawValue`, which may
    // carry a record tail, a fragment, or (leniently) a query. `strict` is passed through so a
    // leniently read space key does not become a strict `SpaceRef`.
    if parts.isSpace, let spaceType = parts.spaceType, let skey = parts.skey {
      spaceRef = try! SpaceRef(
        string: "at://\(parts.authority)/\(SpaceRef.marker)/\(spaceType)/\(skey)", strict: strict)
    } else {
      spaceRef = nil
    }
  }
}

extension ATURI {
  /// Composes a strict AT URI naming a space.
  ///
  /// This initializer can throw for the same reason ``SpaceRef/init(spaceDid:spaceType:skey:)``
  /// does: a ``RecordKey`` obtained leniently does not necessarily satisfy the strict wire format.
  public init(spaceRef: SpaceRef) throws {
    try self.init(string: spaceRef.rawValue)
  }

  /// Composes a strict AT URI naming a record within a space.
  public init(spaceRef: SpaceRef, authorDid: DID, collection: NSID, rkey: RecordKey) throws {
    try self.init(
      string:
        "\(spaceRef.rawValue)/\(authorDid.rawValue)/\(collection.rawValue)/\(rkey.rawValue)"
    )
  }
}

extension ATURI {
  private struct Parts {
    var authority: Substring
    var collection: Substring?
    var rkey: Substring?
    var fragment: Substring?
    var isSpace = false
    var spaceType: Substring?
    var skey: Substring?
    var author: Substring?
  }

  // Restricted-syntax validation per the AT URI spec. When `strict` is false the lenient variant
  // is applied: trailing slash, query, and percent-encoding errors in the fragment are accepted,
  // and `rkey` / `skey` are admitted through `RecordKey.isValidLenient` (non-empty + no path
  // delimiters) instead of the strict record-key grammar.
  private static func parse(_ input: String, strict: Bool = true) -> Parts? {
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
    // Consumes a "/" and reports whether a further segment follows it.
    func consumeSlash() -> Bool {
      guard i < end, input[i] == "/" else { return false }
      i = input.index(after: i)
      return !atSegmentBoundary()
    }

    let authority = scanSegment()
    if authority.isEmpty { return nil }

    var parts = Parts(authority: authority)
    var trailingSlash = false

    if i < end, input[i] == "/" {
      i = input.index(after: i)
      if atSegmentBoundary() {
        trailingSlash = true
      } else {
        let first = scanSegment()
        if first == SpaceRef.marker {
          parts.isSpace = true
          // The space type and the space key are both mandatory, so a URI that stops at the
          // marker is rejected in either mode rather than read as a trailing slash.
          guard consumeSlash() else { return nil }
          parts.spaceType = scanSegment()
          guard consumeSlash() else { return nil }
          parts.skey = scanSegment()
          if i < end, input[i] == "/" {
            i = input.index(after: i)
            if atSegmentBoundary() {
              trailingSlash = true
            } else {
              // The record triple is all-or-nothing: a partial tail is not a shorter URI.
              parts.author = scanSegment()
              guard consumeSlash() else { return nil }
              parts.collection = scanSegment()
              guard consumeSlash() else { return nil }
              parts.rkey = scanSegment()
              if i < end, input[i] == "/" {
                i = input.index(after: i)
                if atSegmentBoundary() {
                  trailingSlash = true
                } else {
                  return nil  // more than six path segments
                }
              }
            }
          }
        } else {
          parts.collection = first
          if i < end, input[i] == "/" {
            i = input.index(after: i)
            if atSegmentBoundary() {
              trailingSlash = true
            } else {
              parts.rkey = scanSegment()
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
    parts.fragment = fragment

    guard i == end else { return nil }

    // Component validation (applies in both strict and lenient).
    if parts.isSpace {
      // A space's identity and membership are keyed on DIDs, so neither the authority nor the
      // author may be a handle.
      guard DID.isValid(authority) else { return nil }
      guard let spaceType = parts.spaceType, NSID.isValid(spaceType) else { return nil }
      if let author = parts.author {
        guard DID.isValid(author) else { return nil }
      }
    } else {
      guard AtIdentifier.isValid(authority) else { return nil }
    }
    if let collection = parts.collection, !NSID.isValid(collection) { return nil }
    if let fragment, !isValidJSONPointer(fragment, strict: strict) { return nil }
    if let skey = parts.skey,
      !(strict ? RecordKey.isValid(skey) : RecordKey.isValidLenient(skey))
    {
      return nil
    }
    if let rkey = parts.rkey, !(strict ? RecordKey.isValid(rkey) : RecordKey.isValidLenient(rkey)) {
      return nil
    }

    // Strict-only constraints.
    if strict, trailingSlash { return nil }
    if strict, hasQuery { return nil }

    return parts
  }

  // MARK: - JSON Pointer fragment

  // JSON Pointer fragment: starts with "/", allowed pointer chars; strict mode additionally
  // requires valid percent-encoding (Swift `removingPercentEncoding` succeeds). Lenient mode
  // accepts malformed `%xx` sequences.
  private static func isValidJSONPointer(_ s: Substring, strict: Bool = true) -> Bool {
    let u = Array(s.utf8)
    guard u.first == slash else { return false }
    for byte in u where !(isAlphanumeric(byte) || pointerPunct.contains(byte)) { return false }
    if strict, String(s).removingPercentEncoding == nil { return false }
    return true
  }
}

// MARK: - ASCII byte helpers

private let slash = UInt8(ascii: "/")

private let pointerPunct = Set("._~:@!$&')(*+,;=%[]/-".utf8)
