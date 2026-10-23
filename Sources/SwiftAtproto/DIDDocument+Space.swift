import Foundation

// Space authority resolution for the permissioned data protocol. The `SpaceAuthorities` article
// describes the model these entries make up.
//
// The first section looks entries up as written and fails when what it was asked for is absent. The
// second names the entries that play each space role. Since the October 22 release, a space
// authority resolves like any other account: `#atproto_pds` is its space host and `#atproto` signs
// its credentials.

// MARK: - Entry lookup

extension DIDDocument {
  /// Whether `id` names the entry that `fragment` refers to.
  ///
  /// A DID document may write an entry id either relative (`#atproto_space`) or absolute
  /// (`did:plc:xxx#atproto_space`); both name the same entry.
  private func matchesID(_ id: String, fragment: String) -> Bool {
    id == "#\(fragment)" || id == "\(did.rawValue)#\(fragment)"
  }

  /// The verification method published under `fragment`, or `nil` when the document has none.
  ///
  /// Returns the entry rather than a parsed key, because `SwiftAtproto` does not depend on
  /// `ATProtoCrypto`. Callers that need a key pass `publicKeyMultibase` to
  /// `ATProtoCrypto.PublicKey.publicKeyFromMultibaseString(string:)`.
  public func verificationMaterial(fragment: String) -> DocVerificationMethod? {
    (verificationMethod ?? []).first { matchesID($0.id, fragment: fragment) }
  }

  /// The service entry published under `fragment`, or `nil` when the document has none. The
  /// endpoint is returned as written; ``endpoint(for:)`` validates it.
  ///
  /// Matching is by id only: a `type` is required for `#atproto_pds` (see ``pdsUrl``) but no type
  /// string is defined for the space host or for a syncer's own service entry.
  public func serviceEntry(fragment: String) -> DocService? {
    (service ?? []).first { matchesID($0.id, fragment: fragment) }
  }

  /// How this authority is addressed when acting as the space host, and therefore the `aud` of a
  /// delegation token or client attestation sent to it.
  ///
  /// A space authority resolves like any other account: its `#atproto_pds` service is its space
  /// host, so the audience is `<did>#atproto_pds`. A `#atproto_space_host` entry published for the
  /// October 1 release is ignored.
  public var spaceHostAudience: String {
    "\(did.rawValue)#atproto_pds"
  }

  /// Resolves the key a space token names in its `kid`.
  ///
  /// A space authority signs delegation tokens and space credentials with its `#atproto` key, and
  /// the `kid` has to be exactly `#atproto`. Any other value, including a missing `#`, the account
  /// key named without it, or the retired `#atproto_space`, is rejected. Unlike
  /// ``spaceSigningKey``, a missing entry is an error.
  public func spaceSigningKey(keyId: String) throws -> DocVerificationMethod {
    guard keyId == "#atproto" else {
      throw VerifyError.unsupportedSpaceKeyId(keyId)
    }
    guard let material = verificationMaterial(fragment: "atproto") else {
      throw VerifyError.missingSpaceSigningKey
    }
    return material
  }

  /// The endpoint to deliver to for `identifier`. `self` must be the document for
  /// `identifier.did`; this performs no DID resolution of its own.
  ///
  /// A bare DID names an account and an account is served by its PDS, so it resolves through
  /// ``pdsUrl``; a fragment-bearing identifier resolves to that service entry.
  public func endpoint(for identifier: ServiceIdentifier) throws -> URL {
    guard identifier.did.rawValue == did.rawValue else {
      throw VerifyError.invalidServiceIdentifier
    }
    guard let fragment = identifier.fragment else {
      return try pdsUrl
    }
    guard let svc = serviceEntry(fragment: fragment) else {
      throw VerifyError.missingServiceEndpoint
    }
    guard let url = Self.parseEndpoint(svc.serviceEndpoint) else {
      throw VerifyError.invalidServiceEndpoint
    }
    return url
  }
}

// MARK: - Space authority roles

extension DIDDocument {
  /// The space host endpoint, which is the account's PDS (``pdsUrl``).
  ///
  /// A space authority resolves like any other account. A `#atproto_space_host` entry published for
  /// the October 1 release is ignored, whatever it points at.
  public var spaceHostUrl: URL {
    get throws { try pdsUrl }
  }

  /// The key this authority signs its space credentials with: the account's `#atproto` signing key.
  /// A `#atproto_space` entry published for the October 1 release is ignored. To verify a credential
  /// that already names its key, use ``spaceSigningKey(keyId:)`` instead of this.
  public var spaceSigningKey: DocVerificationMethod {
    get throws {
      guard let account = verificationMaterial(fragment: "atproto") else {
        throw VerifyError.missingSpaceSigningKey
      }
      return account
    }
  }

  /// The key a syncer encapsulates against to share a MAC secret with this account's repo host:
  /// the `#atproto_kem` verification method. Pass its `publicKeyMultibase` to
  /// `ATProtoCrypto.SpaceKeyEncapsulation.encapsulate(authorKEMKey:)`.
  ///
  /// Until an account publishes one, its space repos cannot be read with a space credential.
  public var spaceKEMKey: DocVerificationMethod {
    get throws {
      guard let key = verificationMaterial(fragment: "atproto_kem") else {
        throw VerifyError.missingSpaceKEMKey
      }
      return key
    }
  }
}

// MARK: - Service identifier

/// A DID with an optional service fragment, naming the entry in that DID's document to deliver to —
/// e.g. `did:web:syncer.example.com#atproto_space_syncer`. `com.atproto.space.registerNotify` takes
/// one of these rather than a bare URL, because `notifyWrite` is delivered with service auth
/// addressed to the identifier itself.
///
/// Parsing rejects malformed input rather than normalizing it, matching the other identifier types
/// in this module: an empty fragment (`did:plc:xxx#`) and a second `#` are both rejected.
public struct ServiceIdentifier: Sendable, Hashable, CustomStringConvertible {
  public let did: DID
  /// Without the leading `#`. Nil when the identifier names a bare DID.
  public let fragment: String?

  /// - Throws: ``LexiconStringFormatError`` when the DID itself is malformed, and
  ///   ``DIDDocument/VerifyError/invalidServiceIdentifier`` when the fragment structure is.
  public init(string: String) throws {
    let parts = string.split(separator: "#", omittingEmptySubsequences: false)
    switch parts.count {
    case 1:
      did = try DID(string: String(parts[0]))
      fragment = nil
    case 2:
      guard !parts[1].isEmpty else {
        throw DIDDocument.VerifyError.invalidServiceIdentifier
      }
      did = try DID(string: String(parts[0]))
      fragment = String(parts[1])
    default:
      throw DIDDocument.VerifyError.invalidServiceIdentifier
    }
  }

  public init(did: DID, fragment: String? = nil) {
    self.did = did
    self.fragment = fragment
  }

  public var rawValue: String {
    guard let fragment else { return did.rawValue }
    return "\(did.rawValue)#\(fragment)"
  }

  public var description: String { rawValue }
}
