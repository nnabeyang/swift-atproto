import Foundation

/// Type for the lexicon `space-ref` string format: a reference to a permissioned data space, as
/// distinct from a record within one.
///
///     at:space/{spaceDid}/{spaceType}/{skey}
///
/// Wire-shape validation only: exactly three slash-separated segments after `at:space/`. Each
/// segment is handed to the validator of its own identifier type — the authority must be a ``DID`` (a handle is not accepted here),
/// the space type must be an ``NSID``, and the space key carries the same syntax requirements as a
/// ``RecordKey``.
///
/// A query string or fragment is rejected, because a space ref names a space and nothing within
/// it. Both fall out of the segment validators, which admit neither `?` nor `#`.
///
/// This parser is self-contained rather than layered on ``ATURI``, which accepts the record URI
/// form as well and therefore has to keep a query, a fragment, and an optional record tail in
/// view. Going the other way is supported: ``ATURI/spaceRef`` yields the space a URI belongs to,
/// whether it names the space itself or a record within it.
///
/// Before the November 24, 2026 Spaces alpha, a space ref was written
/// `at://{spaceDid}/space/{spaceType}/{skey}`. Strict parsing rejects that legacy form. Lenient
/// parsing accepts it and rewrites it to the current form, which becomes ``rawValue``. That
/// support is temporary and goes away before the beta, as it does upstream.
public struct SpaceRef: LexiconStringFormat {
  /// The wire string, kept verbatim, except that a legacy space ref read leniently is rewritten to
  /// the current `at:space/` form.
  public let rawValue: String
  /// The authority that owns the space. Always a DID.
  public let spaceDid: DID
  /// The NSID naming the space type.
  public let spaceType: NSID
  /// The space key: the trailing segment identifying this space within its type.
  public let skey: RecordKey

  public init(string: String) throws {
    try self.init(string: string, strict: true)
  }

  /// When `strict == false`, ``skey`` relaxes to the same structural admission ``RecordKey`` uses
  /// in its own lenient mode, and the legacy `at://{spaceDid}/space/...` form is accepted and
  /// rewritten to the current one. The authority and the space type are validated either way,
  /// matching where the space URI grammar places each check.
  public init(string: String, strict: Bool) throws {
    guard let normalized = SpaceRef.currentForm(of: string, strict: strict),
      let parts = SpaceRef.parse(normalized, strict: strict)
    else {
      throw LexiconStringFormatError.invalid(format: "space-ref", value: string)
    }
    rawValue = normalized
    // `SpaceRef.parse` has already run each component through its identifier-type validator, so
    // the typed inits below cannot throw in practice — the force-tries document that invariant.
    spaceDid = try! DID(string: String(parts.spaceDid))
    spaceType = try! NSID(string: String(parts.spaceType))
    skey = try! RecordKey(string: String(parts.skey), strict: strict)
  }
}

extension SpaceRef {
  /// Composes a strict space ref from its parts.
  ///
  /// This initializer can throw because ``RecordKey`` also supports explicitly lenient values,
  /// which do not necessarily satisfy the strict space-ref wire format.
  public init(spaceDid: DID, spaceType: NSID, skey: RecordKey) throws {
    try self.init(
      string: "\(SpaceRef.uriPrefix)\(spaceDid.rawValue)/\(spaceType.rawValue)/\(skey.rawValue)"
    )
  }
}

extension SpaceRef: CustomStringConvertible {
  public var description: String { rawValue }
}

extension SpaceRef {
  /// The prefix that distinguishes a space URI from a public AT URI, which starts with `at://`.
  public static let uriPrefix = "at:space/"

  /// The path segment that followed the authority in the legacy `at://{spaceDid}/space/...` form.
  private static let legacyMarker = "/space/"

  /// Returns `input` in the current form: unchanged unless it is a legacy space URI, which strict
  /// parsing rejects (nil) and lenient parsing rewrites to `at:space/{spaceDid}/...`, as upstream's
  /// `fromLegacySpaceUri` does. A legacy URI is one whose first path segment after an `at://`
  /// authority is `space` followed by a slash. The rewritten string still goes through the full
  /// parser, so a handle authority or a wrong length is rejected there.
  static func currentForm(of input: String, strict: Bool) -> String? {
    guard input.hasPrefix("at://") else { return input }
    let afterScheme = input.dropFirst(5)
    guard let authorityEnd = afterScheme.firstIndex(where: { $0 == "/" || $0 == "?" || $0 == "#" }),
      afterScheme[authorityEnd...].hasPrefix(legacyMarker)
    else { return input }
    let authority = afterScheme[..<authorityEnd]
    guard !authority.isEmpty, !strict else { return nil }
    let rest = afterScheme[authorityEnd...].dropFirst(legacyMarker.count)
    return "\(uriPrefix)\(authority)/\(rest)"
  }

  private struct Parts {
    var spaceDid: Substring
    var spaceType: Substring
    var skey: Substring
  }

  private static func parse(_ input: String, strict: Bool) -> Parts? {
    // The component validators cap their own lengths, but a lenient `skey` is uncapped, so bound
    // the whole string the way `ATURI` does.
    guard input.utf8.count <= 8192 else { return nil }
    for byte in input.utf8 where !isAllowedURIByte(byte) { return nil }
    guard input.hasPrefix(uriPrefix) else { return nil }

    // Empty subsequences are kept so that an empty segment, a doubled slash, or a trailing slash
    // changes the count or fails a component validator instead of being silently dropped.
    let segments = input.dropFirst(uriPrefix.count).split(
      separator: "/", omittingEmptySubsequences: false)
    guard segments.count == 3 else { return nil }

    let spaceDid = segments[0]
    let spaceType = segments[1]
    let skey = segments[2]
    guard DID.isValid(spaceDid), NSID.isValid(spaceType) else { return nil }
    guard strict ? RecordKey.isValid(skey) : RecordKey.isValidLenient(skey) else { return nil }
    return Parts(spaceDid: spaceDid, spaceType: spaceType, skey: skey)
  }
}
