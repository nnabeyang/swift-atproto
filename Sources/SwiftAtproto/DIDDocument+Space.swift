import Foundation

// Space authority resolution for the permissioned data protocol. The `SpaceAuthorities` article
// describes the model these entries make up.
//
// The file is split in two. The first section looks entries up as written and fails when what it
// was asked for is absent. The second section holds the fallbacks that apply when an entry is not
// published at all.

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
  /// endpoint is returned as written; ``spaceHostUrl`` and ``endpoint(for:)`` validate it.
  ///
  /// Matching is by id only: a `type` is required for `#atproto_pds` (see ``pdsUrl``) but no type
  /// string is defined for the space host or for a syncer's own service entry.
  public func serviceEntry(fragment: String) -> DocService? {
    (service ?? []).first { matchesID($0.id, fragment: fragment) }
  }

  /// How this authority is addressed when acting as the space host, and therefore the `aud` of a
  /// delegation token or client attestation sent to it.
  ///
  /// This is the audience, not necessarily where the request is sent — an authority that publishes
  /// no `#atproto_space_host` entry is still addressed this way while being reached at its PDS.
  public var spaceHostAudience: String {
    "\(did.rawValue)#atproto_space_host"
  }

  /// Resolves the key a space token names in its `kid`.
  ///
  /// Only `atproto`
  /// and `atproto_space` are accepted, with or without a leading `#`. Unlike the fallback property of
  /// the same name, this does not fall back — the token said which key signed it, so a missing entry is an error.
  public func spaceSigningKey(keyId: String) throws -> DocVerificationMethod {
    let fragment = keyId.hasPrefix("#") ? String(keyId.dropFirst()) : keyId
    guard fragment == "atproto" || fragment == "atproto_space" else {
      throw VerifyError.unsupportedSpaceKeyId(keyId)
    }
    guard let material = verificationMaterial(fragment: fragment) else {
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

// MARK: - Fallbacks

extension DIDDocument {
  /// The space host endpoint. Falls back to ``pdsUrl`` when no `#atproto_space_host` entry is
  /// published, per the proposal.
  ///
  /// A published-but-malformed endpoint throws instead of falling back: the fallback is for an
  /// authority that declares no dedicated host, and quietly routing past a misconfigured one would
  /// send space-host traffic to the PDS.
  public var spaceHostUrl: URL {
    get throws {
      guard let svc = serviceEntry(fragment: "atproto_space_host") else {
        return try pdsUrl
      }
      guard let url = Self.parseEndpoint(svc.serviceEndpoint) else {
        throw VerifyError.invalidServiceEndpoint
      }
      return url
    }
  }

  /// The key this authority signs its space credentials with: the dedicated `#atproto_space` entry
  /// when published, otherwise the account's `#atproto` signing key. To verify a credential that
  /// already names its key, use ``spaceSigningKey(keyId:)`` instead of this.
  public var spaceSigningKey: DocVerificationMethod {
    get throws {
      if let dedicated = verificationMaterial(fragment: "atproto_space") {
        return dedicated
      }
      guard let account = verificationMaterial(fragment: "atproto") else {
        throw VerifyError.missingSpaceSigningKey
      }
      return account
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
