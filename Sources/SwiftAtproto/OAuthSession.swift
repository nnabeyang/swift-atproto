import Foundation

public protocol OAuthSession: Sendable {
  var sessionDid: DID { get }
  var audienceDid: DID { get }
  var grantedScopes: ScopesSet { get }
}
