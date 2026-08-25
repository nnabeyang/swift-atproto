import Foundation

// Introspection for the three JWT credential classes of the permissioned data proposal. The
// `SpaceCredentials` article describes what each one is for and how they fit together.
//
// Nothing in this file checks a signature. Doing that means resolving the issuer's DID to a
// document and testing the signature against a key published there, which is the receiving
// service's job, not the holder's; a holder only needs to read what it was handed. Every type here
// is named `Unverified…` and every entry point is labelled `introspecting:` so that a parsed token
// cannot be mistaken for a verified one at a call site.

/// A failure to read a space token.
///
/// A claim that is present but malformed throws the error of its own identifier type instead:
/// ``LexiconStringFormatError`` for `iss` and `sub`, ``DIDDocument/VerifyError`` for `aud`.
///
/// No case carries the token or any part of it, because a credential must not reach a log through
/// an error message.
public enum SpaceTokenError: Error, Hashable, Sendable {
  /// The token is not three base64url segments, a segment is not JSON, or the signature segment is
  /// empty.
  case malformed
  /// The `typ` header names a different credential class than the one being read.
  case wrongType(expected: String, found: String?)
  /// A claim this credential class requires is absent or empty. The payload names the claim, e.g.
  /// `exp` or `cnf.jkt`.
  case missingClaim(String)
  /// A client attestation whose `iss` and `sub` disagree. Both are the `client_id`.
  case clientIDMismatch
}

// MARK: - Credential classes

/// What separates one credential class from another on the wire.
///
/// The three share a shape and differ only in who signs them, who they are addressed to, and how
/// long they live, so the differences are data here rather than three parsers.
private struct SpaceTokenSpec {
  let typ: String
  let requiresAudience: Bool
  let requiresBoundKey: Bool
  /// A single-use token carries the `jti` its recipient remembers in order to refuse a replay. A
  /// credential is reused across hosts and needs none.
  let requiresTokenID: Bool

  static let delegation = SpaceTokenSpec(
    typ: "atproto-space-delegation+jwt",
    requiresAudience: true,
    requiresBoundKey: false,
    requiresTokenID: true)

  static let credential = SpaceTokenSpec(
    typ: "atproto-space-credential+jwt",
    requiresAudience: false,
    requiresBoundKey: true,
    requiresTokenID: false)

  static let clientAttestation = SpaceTokenSpec(
    typ: "atproto-client-attestation+jwt",
    requiresAudience: true,
    requiresBoundKey: false,
    requiresTokenID: true)
}

// MARK: - Shared parsing

/// The claims of a space token as written, with the checks its class prescribes applied and
/// nothing interpreted yet.
private struct SpaceTokenClaims {
  let algorithm: String
  let keyID: String?
  let issuer: String
  let subject: String
  let audience: String?
  let issuedAt: Date?
  let expiresAt: Date
  let tokenID: String?
  let boundKeyThumbprint: String?
}

extension SpaceTokenClaims {
  private struct Header: Decodable {
    let alg: String?
    let typ: String?
    let kid: String?
  }

  private struct Payload: Decodable {
    struct Confirmation: Decodable {
      let jkt: String?
    }

    let iss: String?
    let sub: String?
    let aud: String?
    let iat: Int?
    let exp: Int?
    let jti: String?
    let cnf: Confirmation?
  }

  init(introspecting token: String, as spec: SpaceTokenSpec) throws {
    // Empty subsequences are kept so that an empty segment fails to decode rather than shifting
    // the count and turning a malformed token into a differently malformed one.
    let segments = token.split(separator: ".", omittingEmptySubsequences: false)
    guard segments.count == 3,
      let headerData = base64URLDecoded(segments[0]),
      let payloadData = base64URLDecoded(segments[1]),
      let signature = base64URLDecoded(segments[2]), !signature.isEmpty
    else {
      throw SpaceTokenError.malformed
    }

    let header: Header
    let payload: Payload
    do {
      let decoder = JSONDecoder()
      header = try decoder.decode(Header.self, from: headerData)
      payload = try decoder.decode(Payload.self, from: payloadData)
    } catch {
      // The decoding error names a coding path inside the token, so it is dropped rather than
      // wrapped: an error a caller may log must not carry claims.
      throw SpaceTokenError.malformed
    }

    guard header.typ == spec.typ else {
      throw SpaceTokenError.wrongType(expected: spec.typ, found: header.typ)
    }
    guard let algorithm = header.alg?.nonEmpty else { throw SpaceTokenError.missingClaim("alg") }
    guard let issuer = payload.iss?.nonEmpty else { throw SpaceTokenError.missingClaim("iss") }
    guard let subject = payload.sub?.nonEmpty else { throw SpaceTokenError.missingClaim("sub") }
    guard let expiry = payload.exp else { throw SpaceTokenError.missingClaim("exp") }

    let audience = payload.aud?.nonEmpty
    let thumbprint = payload.cnf?.jkt?.nonEmpty
    let tokenID = payload.jti?.nonEmpty
    if spec.requiresAudience, audience == nil { throw SpaceTokenError.missingClaim("aud") }
    if spec.requiresBoundKey, thumbprint == nil { throw SpaceTokenError.missingClaim("cnf.jkt") }
    if spec.requiresTokenID, tokenID == nil { throw SpaceTokenError.missingClaim("jti") }

    self.algorithm = algorithm
    self.issuer = issuer
    self.subject = subject
    self.audience = audience
    self.tokenID = tokenID
    boundKeyThumbprint = thumbprint
    keyID = header.kid?.nonEmpty
    // JWT spells both instants as whole seconds since the Unix epoch.
    issuedAt = payload.iat.map { Date(timeIntervalSince1970: TimeInterval($0)) }
    expiresAt = Date(timeIntervalSince1970: TimeInterval(expiry))
  }
}

extension String {
  /// `nil` for the empty string, so that a claim written as `""` reads as absent. An empty `iss`
  /// names no one, and treating it as a value would let it satisfy a required claim.
  fileprivate var nonEmpty: String? { isEmpty ? nil : self }
}

// MARK: - Space credential

/// A space credential as its holder reads it: the claims are parsed, the signature is not checked.
///
/// A space authority issues one in exchange for a delegation token, and an application presents it
/// to every repo host serving a repo in the space until it expires. The holder reads three things
/// from it — when to renew (``isExpired(at:clockSkew:)``), which space it covers
/// (``authorizes(_:)``), and which key it is bound to (``isBound(toKeyThumbprint:)``).
///
/// - Important: Parsing establishes nothing about who issued this. Verifying the signature means
///   resolving ``issuer`` to a DID document, taking the key ``keyID`` names, and checking the
///   signature against it — the receiving service's side of the exchange.
public struct UnverifiedSpaceCredential: Sendable, Hashable {
  /// `iss`: the space authority that issued the credential.
  public let issuer: DID
  /// `sub`: the space this credential reads.
  public let space: SpaceRef
  /// `cnf.jkt`: the JWK thumbprint of the key the credential is bound to. A credential is a
  /// whole-space capability presented to many hosts, so it is bound to the holder's DPoP key
  /// rather than being a bearer token.
  public let boundKeyThumbprint: String
  /// `iat`, when the credential carries one.
  public let issuedAt: Date?
  /// `exp`.
  public let expiresAt: Date
  /// `jti`, when the credential carries one. A credential is multi-use, so it need not.
  public let tokenID: String?
  /// `alg`: the JOSE algorithm the signature was produced with.
  public let algorithm: String
  /// `kid`: the entry in the issuer's DID document that names the signing key. Pass it to
  /// ``DIDDocument/spaceSigningKey(keyId:)``.
  public let keyID: String?

  /// Reads a compact JWT as a space credential.
  ///
  /// - Throws: ``SpaceTokenError`` when the structure or a required claim is wrong,
  ///   ``LexiconStringFormatError`` when `iss` is not a DID or `sub` is not a space ref.
  public init(introspecting token: String) throws {
    let claims = try SpaceTokenClaims(introspecting: token, as: .credential)
    issuer = try DID(string: claims.issuer)
    space = try SpaceRef(string: claims.subject)
    // The credential spec requires a bound key, so the claims parser has already refused a token
    // without one — the force-unwrap documents that invariant.
    boundKeyThumbprint = claims.boundKeyThumbprint!
    issuedAt = claims.issuedAt
    expiresAt = claims.expiresAt
    tokenID = claims.tokenID
    algorithm = claims.algorithm
    keyID = claims.keyID
  }
}

extension UnverifiedSpaceCredential {
  /// The tolerance ``isExpired(at:clockSkew:)`` applies unless told otherwise: five seconds.
  public static let defaultClockSkew: TimeInterval = 5

  /// Whether the credential's lifetime has run out by `instant`.
  ///
  /// `clockSkew` widens the window in the permissive direction: the credential still counts as
  /// live for that long past ``expiresAt``, so a clock running a few seconds fast does not discard
  /// one the issuer considers valid. A holder deciding when to renew wants the opposite and should
  /// pass a negative `clockSkew`, or compare against ``expiresAt`` itself.
  public func isExpired(
    at instant: Date = Date(), clockSkew: TimeInterval = defaultClockSkew
  ) -> Bool {
    instant.addingTimeInterval(-clockSkew) >= expiresAt
  }

  /// Whether this credential covers `space`.
  ///
  /// The check a holder makes against the space it asked for, so that a credential minted for a
  /// different space is never presented to a repo host.
  public func authorizes(_ space: SpaceRef) -> Bool {
    self.space == space
  }

  /// Whether this credential is bound to the key with `thumbprint`.
  ///
  /// `thumbprint` is the RFC 7638 thumbprint of the holder's own DPoP key. It is base64url and
  /// therefore case-sensitive, so the comparison is exact.
  public func isBound(toKeyThumbprint thumbprint: String) -> Bool {
    boundKeyThumbprint == thumbprint
  }
}

extension UnverifiedSpaceCredential: CustomStringConvertible {
  /// Names the space and the expiry and stops there. The default reflected description would print
  /// ``boundKeyThumbprint`` and ``tokenID``, which is how a credential ends up in a log.
  public var description: String {
    "UnverifiedSpaceCredential(space: \(space.rawValue), expiresAt: \(expiresAt))"
  }
}

// MARK: - Delegation token

/// A delegation token as a forwarder reads it: the claims are parsed, the signature is not checked.
///
/// A user's PDS mints one to assert that an application is acting on that user's behalf, and the
/// application forwards it to the space authority in exchange for a credential. It is single-use
/// and short-lived.
///
/// - Important: Parsing establishes nothing about who issued this. The authority the token is
///   addressed to is the party that verifies it.
public struct UnverifiedSpaceDelegationToken: Sendable, Hashable {
  /// `iss`: the user delegating.
  public let issuer: DID
  /// `sub`: the space the token is bound to.
  public let space: SpaceRef
  /// `aud`: the space host the token is addressed to, which is
  /// ``DIDDocument/spaceHostAudience`` of the authority.
  public let audience: ServiceIdentifier
  /// `iat`, when the token carries one.
  public let issuedAt: Date?
  /// `exp`.
  public let expiresAt: Date
  /// `jti`: the nonce the authority remembers in order to refuse a replay.
  public let tokenID: String
  /// `alg`: the JOSE algorithm the signature was produced with.
  public let algorithm: String
  /// `kid`: the entry in the issuer's DID document that names the signing key.
  public let keyID: String?

  /// Reads a compact JWT as a delegation token.
  ///
  /// - Throws: ``SpaceTokenError`` when the structure or a required claim is wrong,
  ///   ``LexiconStringFormatError`` when `iss` is not a DID or `sub` is not a space ref, and
  ///   ``DIDDocument/VerifyError/invalidServiceIdentifier`` when `aud` is not a service identifier.
  public init(introspecting token: String) throws {
    let claims = try SpaceTokenClaims(introspecting: token, as: .delegation)
    issuer = try DID(string: claims.issuer)
    space = try SpaceRef(string: claims.subject)
    // The delegation spec requires both, so the claims parser has already refused a token missing
    // either — the force-unwraps document that invariant.
    audience = try ServiceIdentifier(string: claims.audience!)
    tokenID = claims.tokenID!
    issuedAt = claims.issuedAt
    expiresAt = claims.expiresAt
    algorithm = claims.algorithm
    keyID = claims.keyID
  }
}

extension UnverifiedSpaceDelegationToken: CustomStringConvertible {
  /// Withholds ``tokenID`` for the reason ``UnverifiedSpaceCredential/description`` withholds its
  /// own: a replay nonce is not something to print.
  public var description: String {
    "UnverifiedSpaceDelegationToken(space: \(space.rawValue), audience: \(audience.rawValue), expiresAt: \(expiresAt))"
  }
}

// MARK: - Client attestation

/// A client attestation as a reader parses it: the claims are read, the signature is not checked.
///
/// An application signs one of these itself to tell a space authority which application is asking.
/// Producing one is `ATProtoCrypto.ClientAttestation`; the two sides meet only as a JWT string.
///
/// - Important: Parsing establishes nothing about which application signed this. Verifying the
///   signature means resolving ``clientID`` to its metadata document, fetching the JWKS it
///   publishes, and checking the signature against the key ``keyID`` names — all of it the
///   authority's side of the exchange, and none of it possible without network access.
public struct UnverifiedClientAttestation: Sendable, Hashable {
  /// The `client_id` the application publishes its metadata at. `iss` and `sub` both carry it, and
  /// an attestation whose two disagree is rejected, so there is one value here rather than two.
  public let clientID: String
  /// `aud`: the space host the attestation is addressed to.
  public let audience: ServiceIdentifier
  /// `iat`, when the attestation carries one.
  public let issuedAt: Date?
  /// `exp`.
  public let expiresAt: Date
  /// `jti`: the nonce the authority remembers in order to refuse a replay.
  public let tokenID: String
  /// `alg`: the JOSE algorithm the signature was produced with.
  public let algorithm: String
  /// `kid`: the key in the client's published JWKS that signed the attestation.
  public let keyID: String?

  /// Reads a compact JWT as a client attestation.
  ///
  /// - Throws: ``SpaceTokenError`` when the structure or a required claim is wrong — including
  ///   ``SpaceTokenError/clientIDMismatch`` when `iss` and `sub` disagree — and
  ///   ``DIDDocument/VerifyError/invalidServiceIdentifier`` when `aud` is not a service identifier.
  public init(introspecting token: String) throws {
    let claims = try SpaceTokenClaims(introspecting: token, as: .clientAttestation)
    guard claims.issuer == claims.subject else { throw SpaceTokenError.clientIDMismatch }
    clientID = claims.issuer
    // The attestation spec requires both, so the claims parser has already refused a token missing
    // either — the force-unwraps document that invariant.
    audience = try ServiceIdentifier(string: claims.audience!)
    tokenID = claims.tokenID!
    issuedAt = claims.issuedAt
    expiresAt = claims.expiresAt
    algorithm = claims.algorithm
    keyID = claims.keyID
  }
}

extension UnverifiedClientAttestation: CustomStringConvertible {
  /// Withholds ``tokenID`` for the reason ``UnverifiedSpaceCredential/description`` withholds its
  /// own: a replay nonce is not something to print.
  public var description: String {
    "UnverifiedClientAttestation(clientID: \(clientID), audience: \(audience.rawValue), expiresAt: \(expiresAt))"
  }
}
