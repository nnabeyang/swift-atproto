import Foundation

/// Mutable session credentials held by a client.
///
/// Equality compares only the two tokens, so a value counts as unchanged while
/// the session is still the same one.
public protocol XRPCAuth: AnyObject, Sendable, Equatable, Hashable {
  /// The token sent as the `Authorization` bearer for ordinary calls.
  var accessJwt: String { get set }
  /// The token used to obtain a new ``accessJwt``.
  var refreshJwt: String { get set }
  /// The account's handle.
  var handle: String { get set }
  /// The account's DID.
  var did: String { get set }
  /// The PDS endpoint for this account, when known.
  var serviceEndPoint: URL? { get set }
}

extension XRPCAuth {
  public static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.accessJwt == rhs.accessJwt && lhs.refreshJwt == rhs.refreshJwt
  }
}
