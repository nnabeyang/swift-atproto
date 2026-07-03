import Foundation

extension DIDDocument {
  public enum VerifyError: Swift.Error, Sendable {
    case missingPDSService
    case invalidPDSEndpoint
    case invalidDID
    case handleMismatch
  }

  // Preferred selector matches the AT Protocol spec (`#atproto_pds`); the type-based fallback
  // preserves interoperability with older DID documents that predate the fragment convention.
  public var pdsUrl: URL {
    get throws {
      let atprotoPDSID = "\(did.rawValue)#atproto_pds"
      let svc =
        (service ?? []).first {
          ($0.id == "#atproto_pds" || $0.id == atprotoPDSID)
            && $0.type == "AtprotoPersonalDataServer"
        }
        ?? (service ?? []).first { $0.type == "AtprotoPersonalDataServer" }
      guard let svc else { throw VerifyError.missingPDSService }
      guard let url = URL(string: svc.serviceEndpoint),
        let scheme = url.scheme?.lowercased(),
        scheme == "http" || scheme == "https",
        url.host != nil
      else {
        throw VerifyError.invalidPDSEndpoint
      }
      return url
    }
  }

  // First `at://<handle>` entry in `alsoKnownAs` with no collection/rkey. Nil when no bare handle
  // is advertised; callers still need to cross-check it via a resolver before trusting it.
  public var unverifiedHandle: Handle? {
    for aka in alsoKnownAs ?? [] {
      guard let uri = try? ATURI(string: aka),
        uri.collection == nil, uri.rkey == nil,
        case .handle(let h) = uri.authority
      else { continue }
      return h
    }
    return nil
  }

  public struct Verified: Sendable, Hashable {
    public let document: DIDDocument
    public let did: DID
    // `Handle.invalid` when handle verification failed or no handle was advertised.
    public let verifiedHandle: Handle

    public init(document: DIDDocument, did: DID, verifiedHandle: Handle) {
      self.document = document
      self.did = did
      self.verifiedHandle = verifiedHandle
    }
  }

  // Synchronous check for callers that already have both sides of the pair.
  public func verified(expecting handle: Handle, did: DID) throws -> Verified {
    guard let parsed = self.did.typed, parsed == did else { throw VerifyError.invalidDID }
    guard unverifiedHandle == handle else { throw VerifyError.handleMismatch }
    return Verified(document: self, did: did, verifiedHandle: handle)
  }

  // Bidirectional check: parse our advertised DID, look up the advertised handle in the resolver,
  // and require the round-trip to close. On mismatch we return `Handle.invalid` rather than
  // throwing so callers can distinguish "no handle advertised" from "document malformed".
  public func verified(resolver: any DIDHandleResolver) async throws -> Verified {
    guard let did = self.did.typed else { throw VerifyError.invalidDID }
    guard let handle = unverifiedHandle else {
      return Verified(document: self, did: did, verifiedHandle: .invalid)
    }
    let resolved = try await resolver.resolveDID(handle: handle)
    guard resolved == did else {
      return Verified(document: self, did: did, verifiedHandle: .invalid)
    }
    return Verified(document: self, did: did, verifiedHandle: handle)
  }
}

public protocol DIDHandleResolver: Sendable {
  func resolveDID(handle: Handle) async throws -> DID
}
