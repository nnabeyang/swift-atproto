import Foundation

/// Type for the lexicon `space-ref` string format: a reference to a permissioned data space, as
/// distinct from a record within one.
///
///     at://{spaceDid}/space/{spaceType}/{skey}
///
/// Wire-shape validation only: exactly four slash-separated segments after `at://`, with the
/// second one being the literal `space` marker. Each remaining segment is handed to the validator
/// of its own identifier type — the authority must be a ``DID`` (a handle is not accepted here),
/// the space type must be an ``NSID``, and the space key carries the same syntax requirements as a
/// ``RecordKey``.
///
/// A query string or fragment is rejected, because a space ref names a space and nothing within
/// it. Both fall out of the segment validators, which admit neither `?` nor `#`.
///
/// This parser is self-contained rather than layered on ``ATURI``: the lexicon `at-uri` grammar
/// admits at most two path segments below the authority, so it cannot carry a space ref. The
/// six-segment record URI form and its conversion to this type are a separate addition.
public struct SpaceRef: LexiconStringFormat {
  /// The original wire string, kept verbatim (no normalization).
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

  /// When `strict == false`, only ``skey`` relaxes, to the same structural admission
  /// ``RecordKey`` uses in its own lenient mode. The authority and the space type are validated
  /// either way, matching where the space URI grammar places each check.
  public init(string: String, strict: Bool) throws {
    guard let parts = SpaceRef.parse(string, strict: strict) else {
      throw LexiconStringFormatError.invalid(format: "space-ref", value: string)
    }
    rawValue = string
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
      string: "at://\(spaceDid.rawValue)/\(SpaceRef.marker)/\(spaceType.rawValue)/\(skey.rawValue)"
    )
  }
}

extension SpaceRef: CustomStringConvertible {
  public var description: String { rawValue }
}

extension SpaceRef {
  /// The fixed second path segment that distinguishes a space ref from a public AT URI. It
  /// contains no dot, while a collection NSID always contains at least two, so the two forms can
  /// never be confused.
  static let marker = "space"

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
    guard input.hasPrefix("at://") else { return nil }

    // Empty subsequences are kept so that an empty segment, a doubled slash, or a trailing slash
    // changes the count or fails a component validator instead of being silently dropped.
    let segments = input.dropFirst(5).split(separator: "/", omittingEmptySubsequences: false)
    guard segments.count == 4, segments[1] == marker else { return nil }

    let spaceDid = segments[0]
    let spaceType = segments[2]
    let skey = segments[3]
    guard DID.isValid(spaceDid), NSID.isValid(spaceType) else { return nil }
    guard strict ? RecordKey.isValid(skey) : RecordKey.isValidLenient(skey) else { return nil }
    return Parts(spaceDid: spaceDid, spaceType: spaceType, skey: skey)
  }
}
