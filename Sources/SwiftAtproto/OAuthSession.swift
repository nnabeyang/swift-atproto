import Foundation

/// An authenticated OAuth session whose granted scopes gate outgoing calls.
///
/// A client returning a session from `_XRPCCallable.oauthSession` has every
/// request checked against ``grantedScopes`` before it is sent. See
/// <doc:OAuthScopes>.
public protocol OAuthSession: Sendable {
  /// The DID of the account this session authenticates.
  var sessionDid: DID { get }
  /// The DID of the service this session was issued for.
  var audienceDid: DID { get }
  /// The scopes the authorization server granted.
  var grantedScopes: ScopesSet { get }
}
