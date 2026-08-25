import Foundation

/// Adds credentials and proof headers to a prepared XRPC request.
///
/// The request already contains its method, path, query, body, logical
/// destination, and proxy header. `serviceEndpoint` is the resolved base URL
/// used to turn ``XRPCRequestComponents/relativePath`` into the absolute target
/// URI required by DPoP.
public protocol XRPCRequestAuthorizer: Sendable {
  /// Returns the request to send after applying credentials for its destination.
  ///
  /// Implementations may perform asynchronous key access or proof generation
  /// and may throw without invoking the transport.
  func authorize(
    _ requestComponents: XRPCRequestComponents,
    serviceEndpoint: URL
  ) async throws -> XRPCRequestComponents
}

/// A credential selected for an XRPC request or permissioned-data exchange.
///
/// The cases keep ordinary access tokens separate from the three credential
/// classes introduced by permissioned data. This type does not decide how a
/// credential travels: an authorizer applies access and delegation tokens as
/// appropriate, applies a space credential with its DPoP proof, and passes a
/// client attestation in the credential-exchange request body.
public enum XRPCCredential: Sendable, Hashable {
  /// An ordinary access token for the client's own session.
  case accessToken(String)
  /// A user's delegation token forwarded to a space authority.
  case spaceDelegationToken(String)
  /// A space authority credential presented to a repository host.
  case spaceCredential(String)
  /// An application attestation passed in a space-credential exchange body.
  case clientAttestation(String)

  /// The credential's wire value.
  public var value: String {
    switch self {
    case .accessToken(let value), .spaceDelegationToken(let value),
      .spaceCredential(let value), .clientAttestation(let value):
      value
    }
  }
}

extension XRPCCredential: CustomStringConvertible, CustomDebugStringConvertible,
  CustomReflectable
{
  /// Identifies the credential class without revealing its value.
  public var description: String {
    switch self {
    case .accessToken: "XRPCCredential.accessToken(<redacted>)"
    case .spaceDelegationToken: "XRPCCredential.spaceDelegationToken(<redacted>)"
    case .spaceCredential: "XRPCCredential.spaceCredential(<redacted>)"
    case .clientAttestation: "XRPCCredential.clientAttestation(<redacted>)"
    }
  }

  /// Identifies the credential class without revealing its value.
  public var debugDescription: String { description }

  /// Prevents reflection-based logging from exposing the credential value.
  public var customMirror: Mirror {
    Mirror(self, children: ["description": description], displayStyle: .enum)
  }
}
