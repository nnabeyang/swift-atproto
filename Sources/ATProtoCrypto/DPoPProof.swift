import Crypto

#if !canImport(Darwin)
  import FoundationEssentials
#else
  import Foundation
#endif

/// Why a proof cannot be spelled at all, before any signing is attempted.
public enum DPoPProofError: Error, Hashable, Sendable {
  /// The target URL has no scheme or no host, so there is no origin to write an
  /// `htu` from. A `mailto:` or a relative URL lands here.
  case unsupportedTargetURL
}

/// A single-use JWT that proves possession of the key a space credential is
/// bound to, sent alongside the credential on every request (RFC 9449).
///
/// A space credential reads a whole space and is presented to every repo host in
/// it. As a bearer token it would be a shared secret: a host handed one to serve
/// its own repo could replay it against every other host in the space. Binding
/// the credential to a key the holder alone controls, and proving possession of
/// that key per request, is what stops that.
///
/// A proof covers one method and one URL and is not reusable, so build one per
/// request. See <doc:DPoPProofs>.
public struct DPoPProof: Sendable, Hashable {
  /// The HTTP method of the request this proof covers, as `htm`.
  ///
  /// Written verbatim and compared verbatim, so it has to be spelled the way the
  /// request line spells it — `GET`, not `get`.
  public let httpMethod: String

  /// The URL of the request this proof covers.
  ///
  /// Only its origin and path reach the wire; see ``httpTargetURI``.
  public let url: URL

  /// When the proof was issued.
  ///
  /// A proof has no `exp`. A verifier accepts one for ``maximumAge`` past this
  /// instant and no longer, so a proof kept around is a proof about to be
  /// rejected.
  public let issuedAt: Date

  /// The `jti` nonce that makes the proof single-use.
  ///
  /// A verifier remembers it in order to reject a replay, so a value must never
  /// be reused across proofs. ``randomTokenID()`` produces a suitable one.
  public let tokenID: String

  /// The credential this proof is presented with, or `nil` when the request is
  /// the exchange that obtains one.
  ///
  /// Only its SHA-256 digest reaches the wire, as `ath`; the credential itself
  /// is never written into the proof. A verifier requires the two to agree, and
  /// requires `ath` to be *absent* when no credential is being presented, so
  /// this has to track what the request actually carries.
  public let credential: String?

  /// Describes a proof. Nothing is signed until ``signed(with:)``.
  ///
  /// Every claim is supplied by the caller, including the nonce: a proof is
  /// single-use, so reusing one is a mistake this type cannot detect for you.
  public init(
    httpMethod: String,
    url: URL,
    issuedAt: Date,
    tokenID: String,
    credential: String? = nil
  ) {
    self.httpMethod = httpMethod
    self.url = url
    self.issuedAt = issuedAt
    self.tokenID = tokenID
    self.credential = credential
  }

  /// The `htu` this proof carries: ``url`` reduced to its origin and path.
  ///
  /// RFC 9449 §4.2 strips the query and the fragment, so one proof covers a path
  /// whatever query is on it. That is not a relaxation the client may decline:
  /// an XRPC query carries its parameters in the query string, and a proof that
  /// kept them would never match what the verifier computes.
  ///
  /// The scheme and host are lowercased and a default port is dropped, because
  /// the verifier derives its side of the comparison from a parsed URL and gets
  /// a normalized origin either way.
  ///
  /// - Throws: ``DPoPProofError/unsupportedTargetURL`` when ``url`` has no
  ///   scheme or no host.
  public var httpTargetURI: String {
    get throws {
      guard let components = URLComponents(url: url, resolvingAgainstBaseURL: true),
        let scheme = components.scheme?.lowercased(),
        let host = components.percentEncodedHost?.lowercased(),
        !host.isEmpty
      else {
        throw DPoPProofError.unsupportedTargetURL
      }
      var uri = "\(scheme)://\(host)"
      if let port = components.port, port != Self.defaultPort(forScheme: scheme) {
        uri += ":\(port)"
      }
      // An origin with nothing after it still has a path, and it is `/`.
      let path = components.percentEncodedPath
      return uri + (path.isEmpty ? "/" : path)
    }
  }

  /// Signs the proof with `key`, returning it as a compact JWS.
  ///
  /// The public half of `key` is embedded in the `jwk` header, which is how a
  /// verifier checks the signature without having been told the key in advance.
  /// It then compares that key's thumbprint against the `cnf.jkt` of the
  /// credential being presented, so `key` has to be the key the credential was
  /// bound to.
  ///
  /// ``issuedAt`` becomes `iat`, which JWT spells as whole seconds since the
  /// Unix epoch, so any sub-second part is truncated.
  ///
  /// - Throws: ``DPoPProofError/unsupportedTargetURL`` when ``url`` cannot be
  ///   written as an `htu`, and whatever ``PrivateKey/sign(_:)`` throws for
  ///   `key`'s type.
  public func signed(with key: PrivateKey) throws -> String {
    try compactJWS(
      header: Header(alg: key.type.jwsAlgorithm, jwk: key.publicKey.bareJWK),
      payload: Payload(
        ath: credential.map(Self.credentialHash),
        htm: httpMethod,
        htu: httpTargetURI,
        iat: Int(issuedAt.timeIntervalSince1970),
        jti: tokenID),
      signedWith: key)
  }

  /// A fresh `jti`: 16 random bytes as lowercase hexadecimal.
  ///
  /// Each proof needs its own, so call this once per proof rather than holding
  /// onto a value.
  public static func randomTokenID() -> String {
    randomHexTokenID()
  }

  /// The longest a verifier accepts a proof after its `iat` — 60 seconds.
  ///
  /// A proof carries no `exp` of its own, so this is the lifetime, and it is the
  /// verifier's constant rather than something the holder can extend.
  public static let maximumAge: TimeInterval = 60

  /// The `ath` claim for `credential`: the base64url SHA-256 of its octets.
  private static func credentialHash(_ credential: String) -> String {
    base64URLEncoded(Data(SHA256.hash(data: Data(credential.utf8))))
  }

  private static func defaultPort(forScheme scheme: String) -> Int? {
    switch scheme {
    case "https": 443
    case "http": 80
    default: nil
    }
  }

  private struct Header: Encodable {
    // Fixed by RFC 9449 §4.2. A verifier rejects any other `typ`, which is what
    // keeps a proof from being accepted anywhere a JWT is read.
    let typ = "dpop+jwt"
    let alg: String
    // No `kid`: the key travels in the proof itself, so there is nothing to name
    // it against.
    let jwk: BareJWK
  }

  private struct Payload: Encodable {
    // Absent when obtaining a credential rather than presenting one, which the
    // synthesized encoding gives us for a `nil` optional.
    let ath: String?
    let htm: String
    let htu: String
    let iat: Int
    let jti: String
  }
}

extension DPoPProof: CustomStringConvertible {
  /// Withholds ``credential`` and ``tokenID``. The default reflected description
  /// would print both, and a proof is most likely to be described while being
  /// logged.
  public var description: String {
    """
    DPoPProof(httpMethod: \(httpMethod), url: \(url), issuedAt: \(issuedAt), \
    presentsCredential: \(credential != nil))
    """
  }
}
