import Foundation

/// A resolved host for one XRPC request.
///
/// The case preserves why the host was selected even when a space host falls
/// back to the same URL as its PDS. Request authorizers can therefore select a
/// credential from the logical destination as well as build an absolute URL
/// from ``serviceEndpoint``.
public enum XRPCRequestDestination: Sendable, Hashable {
  /// A member's permissioned repository host, resolved from its
  /// `#atproto_pds` service.
  case repoHost(did: DID, serviceEndpoint: URL)
  /// A space authority's host, resolved from `#atproto_space_host` or its PDS
  /// fallback.
  case spaceHost(did: DID, serviceEndpoint: URL)

  /// The DID whose document supplied this destination.
  public var did: DID {
    switch self {
    case .repoHost(let did, _), .spaceHost(let did, _): did
    }
  }

  /// The base URL to which the request's `/xrpc/<nsid>` path is appended.
  public var serviceEndpoint: URL {
    switch self {
    case .repoHost(_, let serviceEndpoint), .spaceHost(_, let serviceEndpoint):
      serviceEndpoint
    }
  }
}

/// Resolves DIDs to documents used for XRPC host discovery.
///
/// Implementations own caching and cache invalidation. The default host
/// helpers validate that the returned document belongs to the requested DID,
/// then use ``DIDDocument/pdsUrl`` and ``DIDDocument/spaceHostUrl`` to derive
/// validated endpoints.
public protocol DIDDocumentResolver: Sendable {
  /// Fetches the current document for `did`.
  func resolveDIDDocument(for did: DID) async throws -> DIDDocument
}

extension DIDDocumentResolver {
  /// Resolves `did` to its permissioned repository host.
  ///
  /// Errors from document retrieval pass through unchanged. Invalid or missing
  /// document entries throw the corresponding ``DIDDocument/VerifyError``.
  public func resolveRepoHost(for did: DID) async throws -> XRPCRequestDestination {
    let document = try await matchingDocument(for: did)
    return .repoHost(did: did, serviceEndpoint: try document.pdsUrl)
  }

  /// Resolves `did` to its space host, falling back to its PDS when the
  /// document publishes no `#atproto_space_host` service.
  ///
  /// Errors from document retrieval pass through unchanged. Invalid or missing
  /// document entries throw the corresponding ``DIDDocument/VerifyError``.
  public func resolveSpaceHost(for did: DID) async throws -> XRPCRequestDestination {
    let document = try await matchingDocument(for: did)
    return .spaceHost(did: did, serviceEndpoint: try document.spaceHostUrl)
  }

  private func matchingDocument(for did: DID) async throws -> DIDDocument {
    let document = try await resolveDIDDocument(for: did)
    guard document.did.typed == did else {
      throw DIDDocument.VerifyError.invalidDID
    }
    return document
  }
}
