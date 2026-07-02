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
      let svc =
        (service ?? []).first { $0.id == "#atproto_pds" }
        ?? (service ?? []).first { $0.type == "AtprotoPersonalDataServer" }
      guard let svc else { throw VerifyError.missingPDSService }
      guard let url = URL(string: svc.serviceEndpoint) else { throw VerifyError.invalidPDSEndpoint }
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
}
