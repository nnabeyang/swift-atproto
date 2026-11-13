import Crypto
import Multibase

#if !canImport(Darwin)
  import FoundationEssentials
#else
  import Foundation
#endif

/// Why a space MAC could not be established, read, or computed.
///
/// No case carries a secret, so an error is safe to log. A repo host reports
/// every one of these to a syncer as `BadSpaceMac`.
public enum SpaceMACError: Error, Hashable, Sendable {
  /// A KEM key or key share is not a P-256 `did:key` or multikey.
  case invalidKey
  /// The header is absent.
  case missingHeader
  /// The header is not a Structured Field Dictionary, or a member has the
  /// wrong kind of value.
  case malformedHeader
  /// The header names another MAC type than the method uses.
  case unsupportedType
  /// The header names another version than the MAC type is on.
  case unsupportedVersion
  /// A string bound into a MAC is longer than its uint16 length prefix allows.
  case fieldTooLong
  /// No signature carries the profile's `tag`, or its `Signature` member is
  /// absent or not a byte sequence without parameters.
  case missingSignature
  /// More than one signature or MAC request carries the profile's `tag`.
  case duplicateSignature
  /// The signature or MAC request covers something other than exactly the
  /// profile's field, flagged `sf`.
  case unexpectedComponents
  /// The `alg` parameter names another algorithm than `hmac-sha256`.
  case unsupportedAlgorithm
  /// A MAC request carries a parameter other than `keyid`, `tag`, and `alg`.
  case unsupportedParameter
  /// The signature's `keyid` is not the key share the MAC was requested with.
  case keyIDMismatch
  /// A MAC request was answered with the other profile's field.
  case profileMismatch
  /// The MAC does not authenticate the covered field.
  case macMismatch
  /// The covered field is authentic but describes another commit or record
  /// than the response carries.
  case fieldMismatch
}

/// What a space MAC authenticates, named by the `tag` of its MAC request and
/// signature.
public enum SpaceMACProfile: String, Hashable, Sendable, CaseIterable {
  /// A repo commit: `getLatestCommit`, `getRepo`, and `listRepoOps`. The MAC
  /// covers `Atproto-Space-Commit`.
  case commit = "atproto-space-commit"
  /// A record's URI and CID: `getRecord`. The MAC covers
  /// `Atproto-Space-Record`.
  case record = "atproto-space-record"

  /// The lowercased name of the field the MAC covers, which is also the
  /// profile's `tag`.
  public var coveredFieldName: String { rawValue }
}

/// The commit an `Atproto-Space-Commit` field describes: the fields of
/// `com.atproto.space.defs#commit`.
public struct SpaceMACCommitField: Hashable, Sendable {
  /// The commit format version.
  public var ver: Int
  /// The DID of the repo's author.
  public var repo: String
  /// The space URI.
  public var space: String
  /// The commit revision.
  public var rev: String
  /// The 32-byte SHA-256 digest of the repo's LtHash state.
  public var data: Data

  /// Creates the description of a commit.
  public init(ver: Int, repo: String, space: String, rev: String, data: Data) {
    self.ver = ver
    self.repo = repo
    self.space = space
    self.rev = rev
    self.data = data
  }
}

/// The record an `Atproto-Space-Record` field names.
public struct SpaceMACRecordField: Hashable, Sendable {
  /// The record's full space URI.
  public var uri: String
  /// The record's CID as a string.
  public var cid: String

  /// Creates the description of a record.
  public init(uri: String, cid: String) {
    self.uri = uri
    self.cid = cid
  }
}

/// The fields of a response that a syncer checks its MAC with.
///
/// Each is the field value as received, or `nil` when the response lacks the
/// field. A field sent on several lines is passed with its values joined by
/// commas, as `HTTPFields` returns it.
public struct SpaceMACResponse: Hashable, Sendable {
  /// The field the profile covers: `Atproto-Space-Commit` or
  /// `Atproto-Space-Record`.
  public var coveredField: String?
  /// The `Signature-Input` field.
  public var signatureInput: String?
  /// The `Signature` field.
  public var signature: String?

  /// Creates the fields from their values.
  public init(coveredField: String?, signatureInput: String?, signature: String?) {
    self.coveredField = coveredField
    self.signatureInput = signatureInput
    self.signature = signature
  }

  /// Reads the fields for `profile` with `field`, which is given each
  /// lowercased field name and returns its value.
  public init(profile: SpaceMACProfile, field: (String) throws -> String?) rethrows {
    self.init(
      coveredField: try field(profile.coveredFieldName),
      signatureInput: try field(SpaceMAC.signatureInputFieldName),
      signature: try field(SpaceMAC.signatureFieldName))
  }
}

/// A MAC request, as a repo host reads it from `Accept-Signature`.
public struct SpaceMACRequest: Hashable, Sendable {
  /// The profile the request is for.
  public let profile: SpaceMACProfile
  /// The label the MAC is requested under, which the response uses.
  public let label: String
  /// The syncer's key share, to decapsulate with
  /// ``SpaceKeyEncapsulation/decapsulate(keyShare:authorKEMKey:)``.
  public let keyShare: String
  /// The requested covered components and parameters, serialized as the
  /// response's `Signature-Input` member uses them.
  public let signatureParameters: String
}

/// What a space MAC authenticates, as named in the `type` of its headers.
public enum SpaceMACType: String, Hashable, Sendable, CaseIterable {
  /// A repo commit: `getLatestCommit`, `getRepo`, and `listRepoOps`.
  case repo = "atproto-space-repo"
  /// A record's URI and CID: `getRecord`.
  case record = "atproto-space-record"

  /// The version the type is on, sent as `ver`. A commit MAC shares its
  /// version with the commit format.
  public var version: Int { 1 }
}

/// The shared secret a syncer establishes with a repo host for one request.
///
/// The syncer encapsulates against the author's `#atproto_kem` key, sends
/// ``keyShare`` with its MAC request, and keeps ``sharedSecret`` to verify the
/// MAC the response carries. The secret is an HPKE secret export
/// ([RFC 9180 §6.2](https://www.rfc-editor.org/rfc/rfc9180#section-6.2)) in
/// base mode, with DHKEM(P-256, HKDF-SHA256), HKDF-SHA256, the Export-only
/// AEAD, the `info` `atproto-mac`, and an empty exporter context, so nothing
/// is encrypted.
///
/// Use a new encapsulation for every request, including retries and each page
/// of a paginated response. It is unrelated to the key a space credential is
/// bound to.
public struct SpaceKeyEncapsulation: Sendable {
  /// HPKE's `enc`, the syncer's ephemeral P-256 public key, as a `did:key`.
  /// HPKE encodes `enc` as an uncompressed point, but a `did:key` carries the
  /// compressed one.
  public let keyShare: String

  /// The 32-byte secret that keys the response MAC.
  public let sharedSecret: SymmetricKey

  /// Encapsulates against `authorKEMKey`, a P-256 `did:key` or the
  /// `publicKeyMultibase` of an `#atproto_kem` verification method.
  ///
  /// - Throws: ``SpaceMACError/invalidKey`` when the key is not P-256.
  public static func encapsulate(authorKEMKey: String) throws -> Self {
    let author = try Self.agreementKey(authorKEMKey)
    do {
      let sender = try HPKE.Sender(recipientKey: author, ciphersuite: ciphersuite, info: info)
      let enc = try P256.Signing.PublicKey(x963Representation: sender.encapsulatedKey)
      return Self(
        keyShare: PublicKey(type: .p256, raw: .p256(enc)).did,
        sharedSecret: try sender.exportSecret(context: Data(), outputByteCount: 32))
    } catch {
      throw SpaceMACError.invalidKey
    }
  }

  /// The repo host's side: derives the secret for `keyShare` with the
  /// author's KEM private key.
  ///
  /// - Throws: ``SpaceMACError/invalidKey`` when `keyShare` or `authorKEMKey`
  ///   is not P-256.
  public static func decapsulate(keyShare: String, authorKEMKey: PrivateKey) throws -> SymmetricKey {
    guard authorKEMKey.type == .p256 else { throw SpaceMACError.invalidKey }
    return try export(
      enc: try agreementKey(keyShare).x963Representation,
      authorKEMKey: authorKEMKey, info: info, context: Data())
  }

  /// The secret HPKE exports for `enc` under `info` and `context`, as the
  /// repo host derives it. Separate from ``decapsulate(keyShare:authorKEMKey:)``
  /// so that the published test vectors, which use another `info`, can be
  /// checked.
  static func export(enc: Data, authorKEMKey: PrivateKey, info: Data, context: Data) throws -> SymmetricKey {
    do {
      let author = try P256.KeyAgreement.PrivateKey(
        rawRepresentation: authorKEMKey.rawRepresentation)
      let recipient = try HPKE.Recipient(
        privateKey: author, ciphersuite: ciphersuite, info: info, encapsulatedKey: enc)
      return try recipient.exportSecret(context: context, outputByteCount: 32)
    } catch {
      throw SpaceMACError.invalidKey
    }
  }

  /// KEM `0x0010`, KDF `0x0001`, and AEAD `0xFFFF`.
  private static let ciphersuite = HPKE.Ciphersuite(
    kem: .P256_HKDF_SHA256, kdf: .HKDF_SHA256, aead: .exportOnly)

  /// A fixed label that ties the secret to this protocol.
  private static let info = Data("atproto-mac".utf8)

  // The multicodec prefix of a P-256 public key, 0x1200 as an unsigned varint.
  private static let p256Multicodec: [UInt8] = [0x80, 0x24]

  static func agreementKey(_ key: String) throws -> P256.KeyAgreement.PublicKey {
    let multibase = key.hasPrefix("did:key:") ? String(key.dropFirst("did:key:".count)) : key
    guard multibase.hasPrefix("z"),
      let decoded = try? BaseEncoding.decode(multibase), decoded.base == .base58btc,
      decoded.data.starts(with: p256Multicodec)
    else { throw SpaceMACError.invalidKey }
    let point = decoded.data.dropFirst(p256Multicodec.count)
    do {
      // Keys written before compressed multikeys carry the 64-byte coordinates.
      return point.count == 64
        ? try P256.KeyAgreement.PublicKey(rawRepresentation: point)
        : try P256.KeyAgreement.PublicKey(compressedRepresentation: point)
    } catch {
      throw SpaceMACError.invalidKey
    }
  }
}

/// The MACs that authenticate space commits and records to a syncer, and the
/// headers that carry them.
///
/// A space repo commit carries no signature. The syncer and the repo host
/// share a secret for each request (``SpaceKeyEncapsulation``), and the host
/// returns an HMAC-SHA256 in `Atproto-Space-Mac`. A leaked response therefore
/// proves nothing about authorship to a third party.
public enum SpaceMAC {
  /// The request header that asks for a MAC and carries the key share.
  public static let wantMACHeaderName = "atproto-space-want-mac"

  /// The response header that carries the MAC.
  public static let macHeaderName = "atproto-space-mac"

  /// The `Atproto-Space-Want-Mac` value for `type`, for example
  /// `type="atproto-space-repo", ver=1, key_share="did:key:zDna…"`.
  public static func wantMACHeader(type: SpaceMACType, keyShare: String) -> String {
    "type=\"\(type.rawValue)\", ver=\(type.version), key_share=\"\(keyShare)\""
  }

  /// The `Atproto-Space-Mac` value for `type` and `mac`, with the MAC as a
  /// padded base64 byte sequence.
  public static func macHeader(type: SpaceMACType, mac: Data) -> String {
    "type=\"\(type.rawValue)\", ver=\(type.version), mac=:\(mac.base64EncodedString()):"
  }

  /// The `key_share` of an `Atproto-Space-Want-Mac` value, after checking its
  /// `type` and `ver`.
  public static func keyShare(fromWantMACHeader value: String?, type: SpaceMACType) throws -> String {
    guard case .string(let keyShare) = try members(of: value, type: type)["key_share"] else {
      throw SpaceMACError.malformedHeader
    }
    return keyShare
  }

  /// The MAC of an `Atproto-Space-Mac` value, after checking its `type` and
  /// `ver`.
  public static func mac(fromMACHeader value: String?, type: SpaceMACType) throws -> Data {
    guard case .bytes(let mac) = try members(of: value, type: type)["mac"] else {
      throw SpaceMACError.malformedHeader
    }
    return mac
  }

  /// The commit MAC:
  ///
  /// ```
  /// context = "atproto-space-repo-v1"
  ///    || uint16be(len(space)) || space
  ///    || uint16be(len(repo))  || repo
  ///    || uint16be(len(rev))   || rev
  /// mac = HMAC-SHA256(shared_secret, context || data)
  /// ```
  public static func commitMAC(
    sharedSecret: SymmetricKey, space: String, repo: String, rev: String, data: Data
  ) throws -> Data {
    Data(
      HMAC<SHA256>.authenticationCode(
        for: try commitMessage(space: space, repo: repo, rev: rev, data: data),
        using: sharedSecret))
  }

  /// Whether `mac` authenticates the commit, compared in constant time.
  public static func isValidCommitMAC(
    _ mac: Data, sharedSecret: SymmetricKey, space: String, repo: String, rev: String, data: Data
  ) -> Bool {
    guard let message = try? commitMessage(space: space, repo: repo, rev: rev, data: data) else {
      return false
    }
    return HMAC<SHA256>.isValidAuthenticationCode(mac, authenticating: message, using: sharedSecret)
  }

  /// The record MAC over the full space record URI and the binary CID:
  ///
  /// ```
  /// context = "atproto-space-record-v1" || uint16be(len(uri)) || uri
  /// mac = HMAC-SHA256(shared_secret, context || record_cid_bytes)
  /// ```
  public static func recordMAC(sharedSecret: SymmetricKey, uri: String, cid: Data) throws -> Data {
    Data(
      HMAC<SHA256>.authenticationCode(
        for: try recordMessage(uri: uri, cid: cid), using: sharedSecret))
  }

  /// Whether `mac` authenticates the record's URI and CID, compared in
  /// constant time.
  public static func isValidRecordMAC(
    _ mac: Data, sharedSecret: SymmetricKey, uri: String, cid: Data
  ) -> Bool {
    guard let message = try? recordMessage(uri: uri, cid: cid) else { return false }
    return HMAC<SHA256>.isValidAuthenticationCode(mac, authenticating: message, using: sharedSecret)
  }

  private static func commitMessage(space: String, repo: String, rev: String, data: Data) throws -> Data {
    var message = Data("\(SpaceMACType.repo.rawValue)-v\(SpaceMACType.repo.version)".utf8)
    for field in [space, repo, rev] {
      message += try lengthPrefixed(field)
    }
    return message + data
  }

  private static func recordMessage(uri: String, cid: Data) throws -> Data {
    Data("\(SpaceMACType.record.rawValue)-v\(SpaceMACType.record.version)".utf8)
      + (try lengthPrefixed(uri)) + cid
  }

  private static func lengthPrefixed(_ value: String) throws -> Data {
    let bytes = Data(value.utf8)
    guard bytes.count <= Int(UInt16.max) else { throw SpaceMACError.fieldTooLong }
    return Data([UInt8(bytes.count >> 8), UInt8(bytes.count & 0xff)]) + bytes
  }

  private static func members(of value: String?, type: SpaceMACType) throws -> [String: StructuredBareItem] {
    guard let value else { throw SpaceMACError.missingHeader }
    guard let dictionary = StructuredDictionary.parse(value) else {
      throw SpaceMACError.malformedHeader
    }
    var members: [String: StructuredBareItem] = [:]
    for (key, member) in dictionary.members.entries {
      // An inner list is kept out, so that a caller expecting a bare item
      // treats it as malformed.
      if case .item(let item) = member { members[key] = item.bareItem }
    }
    guard case .string(type.rawValue) = members["type"] else {
      throw SpaceMACError.unsupportedType
    }
    guard case .integer(Int64(type.version)) = members["ver"] else {
      throw SpaceMACError.unsupportedVersion
    }
    return members
  }
}

// MARK: - HTTP message signatures

/// A space MAC is an HTTP message signature
/// ([RFC 9421](https://www.rfc-editor.org/rfc/rfc9421.html)) with the
/// `hmac-sha256` algorithm, keyed by the secret of a ``SpaceKeyEncapsulation``.
/// The syncer asks for it in `Accept-Signature`; the repo host answers with
/// the profile's field and a signature that covers exactly that field.
extension SpaceMAC {
  /// The request field that asks for a MAC.
  public static let acceptSignatureFieldName = "accept-signature"

  /// The response field that carries the signature's covered components and
  /// parameters.
  public static let signatureInputFieldName = "signature-input"

  /// The response field that carries the MAC.
  public static let signatureFieldName = "signature"

  /// The signature algorithm of every space MAC.
  public static let algorithm = "hmac-sha256"

  /// The label ``acceptSignature(profile:keyShare:)`` requests a MAC under.
  /// A host answers under the requested label, but the MAC is found by its
  /// `tag`, because labels carry no meaning (RFC 9421 §7.2.5).
  public static let label = "mac"

  // MARK: Syncer

  /// The `Accept-Signature` value that requests a MAC for `profile`, keyed
  /// by the secret `keyShare` was encapsulated with, for example
  /// `mac=("atproto-space-commit";sf);keyid="did:key:zDna…";tag="atproto-space-commit"`.
  public static func acceptSignature(profile: SpaceMACProfile, keyShare: String) -> String {
    label + "="
      + StructuredFieldSerializer.innerList(
        StructuredInnerList(
          components(profile),
          parameters: .init([("keyid", .string(keyShare)), ("tag", .string(profile.rawValue))])))
  }

  /// Checks the MAC of a response to an `atproto-space-commit` request, then
  /// that the `Atproto-Space-Commit` field it covers describes `commit`, the
  /// commit in the response body or the metadata of the STAR archive.
  ///
  /// Comparing `commit` with the repo and space that were requested is the
  /// caller's to do.
  ///
  /// - Throws: ``SpaceMACError/fieldMismatch`` when the field describes
  ///   another commit, or another ``SpaceMACError`` when the MAC does not
  ///   verify, as ``verifyRecord(_:record:encapsulation:)`` describes.
  public static func verifyCommit(
    _ response: SpaceMACResponse, commit: SpaceMACCommitField, encapsulation: SpaceKeyEncapsulation
  ) throws {
    let field = try verify(response, profile: .commit, encapsulation: encapsulation)
    guard case .integer(let ver)? = field.bareItem("ver"),
      case .string(let repo)? = field.bareItem("repo"),
      case .string(let space)? = field.bareItem("space"),
      case .string(let rev)? = field.bareItem("rev"),
      case .bytes(let data)? = field.bareItem("data"), let ver = Int(exactly: ver)
    else { throw SpaceMACError.malformedHeader }
    guard SpaceMACCommitField(ver: ver, repo: repo, space: space, rev: rev, data: data) == commit
    else { throw SpaceMACError.fieldMismatch }
  }

  /// Checks the MAC of a response to an `atproto-space-record` request, then
  /// that the `Atproto-Space-Record` field it covers names `record`: the URI
  /// that was requested and the CID computed from the returned record.
  ///
  /// - Throws: ``SpaceMACError/missingHeader`` when a field is absent;
  ///   ``SpaceMACError/malformedHeader`` when one is not a Structured Field
  ///   Dictionary of the expected shape; ``SpaceMACError/missingSignature`` or
  ///   ``SpaceMACError/duplicateSignature`` when not exactly one signature
  ///   carries the profile's `tag`; ``SpaceMACError/unexpectedComponents``,
  ///   ``SpaceMACError/unsupportedAlgorithm``, or
  ///   ``SpaceMACError/keyIDMismatch`` when that signature covers something
  ///   else, names another algorithm, or names another key share;
  ///   ``SpaceMACError/macMismatch`` when the MAC does not verify; and
  ///   ``SpaceMACError/fieldMismatch`` when the field names another record.
  public static func verifyRecord(
    _ response: SpaceMACResponse, record: SpaceMACRecordField, encapsulation: SpaceKeyEncapsulation
  ) throws {
    let field = try verify(response, profile: .record, encapsulation: encapsulation)
    guard case .string(let uri)? = field.bareItem("uri"),
      case .string(let cid)? = field.bareItem("cid")
    else { throw SpaceMACError.malformedHeader }
    guard SpaceMACRecordField(uri: uri, cid: cid) == record else {
      throw SpaceMACError.fieldMismatch
    }
  }

  // MARK: Repo host

  /// The MAC requested for `profile` in an `Accept-Signature` value, or `nil`
  /// when the value is absent or requests none for `profile`. Requests with
  /// other tags are ignored.
  ///
  /// - Throws: ``SpaceMACError/malformedHeader`` when the value is not a
  ///   Structured Field Dictionary; ``SpaceMACError/duplicateSignature`` when
  ///   it requests more than one MAC with the profile's `tag`;
  ///   ``SpaceMACError/unexpectedComponents`` when the request covers
  ///   something other than the profile's field;
  ///   ``SpaceMACError/unsupportedParameter`` or
  ///   ``SpaceMACError/unsupportedAlgorithm`` when it asks for parameters the
  ///   host cannot fulfill; and ``SpaceMACError/invalidKey`` when `keyid` is
  ///   not a P-256 `did:key`.
  public static func request(
    fromAcceptSignature value: String?, profile: SpaceMACProfile
  ) throws -> SpaceMACRequest? {
    guard let value else { return nil }
    guard let requests = StructuredDictionary.parse(value) else {
      throw SpaceMACError.malformedHeader
    }
    let tagged = tagged(requests, profile: profile)
    guard tagged.count <= 1 else { throw SpaceMACError.duplicateSignature }
    guard let (label, list) = tagged.first else { return nil }
    guard list.items == components(profile) else { throw SpaceMACError.unexpectedComponents }
    for key in list.parameters.keys where !["keyid", "tag", "alg"].contains(key) {
      throw SpaceMACError.unsupportedParameter
    }
    try checkAlgorithm(list.parameters)
    guard case .string(let keyShare)? = list.parameters["keyid"], keyShare.hasPrefix("did:key:")
    else { throw SpaceMACError.invalidKey }
    _ = try SpaceKeyEncapsulation.agreementKey(keyShare)
    return SpaceMACRequest(
      profile: profile, label: label, keyShare: keyShare,
      signatureParameters: StructuredFieldSerializer.innerList(list))
  }

  /// The fields that answer `request` for `commit`: `Atproto-Space-Commit`,
  /// `Signature-Input`, `Signature`, and `Vary`, keyed by `sharedSecret`, the
  /// secret decapsulated from the request's key share.
  ///
  /// - Throws: ``SpaceMACError/profileMismatch`` when `request` is not for
  ///   ``SpaceMACProfile/commit``, and ``SpaceMACError/malformedHeader`` when
  ///   a string is not printable ASCII, which a Structured Field String
  ///   cannot carry.
  public static func responseFields(
    commit: SpaceMACCommitField, request: SpaceMACRequest, sharedSecret: SymmetricKey
  ) throws -> [(name: String, value: String)] {
    try responseFields(
      [
        ("ver", .integer(Int64(commit.ver))), ("repo", .string(commit.repo)),
        ("space", .string(commit.space)), ("rev", .string(commit.rev)), ("data", .bytes(commit.data)),
      ],
      profile: .commit, request: request, sharedSecret: sharedSecret)
  }

  /// The fields that answer `request` for `record`: `Atproto-Space-Record`,
  /// `Signature-Input`, `Signature`, and `Vary`, keyed by `sharedSecret`.
  ///
  /// - Throws: As ``responseFields(commit:request:sharedSecret:)`` does, with
  ///   ``SpaceMACError/profileMismatch`` when `request` is not for
  ///   ``SpaceMACProfile/record``.
  public static func responseFields(
    record: SpaceMACRecordField, request: SpaceMACRequest, sharedSecret: SymmetricKey
  ) throws -> [(name: String, value: String)] {
    try responseFields(
      [("uri", .string(record.uri)), ("cid", .string(record.cid))],
      profile: .record, request: request, sharedSecret: sharedSecret)
  }

  // MARK: Shared

  /// The covered component list of a profile's MAC: its field, flagged `sf`.
  private static func components(_ profile: SpaceMACProfile) -> [StructuredItem] {
    [StructuredItem(.string(profile.coveredFieldName), parameters: .init([("sf", .boolean(true))]))]
  }

  /// The inner lists in a `Signature-Input` or `Accept-Signature` value whose
  /// `tag` is the profile's, with their labels.
  private static func tagged(
    _ members: StructuredDictionary, profile: SpaceMACProfile
  ) -> [(label: String, list: StructuredInnerList)] {
    members.members.entries.compactMap { label, member in
      guard case .innerList(let list) = member,
        list.parameters["tag"] == .string(profile.rawValue)
      else { return nil }
      return (label, list)
    }
  }

  private static func checkAlgorithm(_ parameters: StructuredParameters) throws {
    if let alg = parameters["alg"], alg != .string(algorithm) {
      throw SpaceMACError.unsupportedAlgorithm
    }
  }

  /// The signature base of RFC 9421 §2.5 for a MAC over one `sf` field: the
  /// component line, then the parameters, joined by single line feeds with no
  /// trailing one.
  private static func signatureBase(
    profile: SpaceMACProfile, field: StructuredDictionary, signatureParameters: String
  ) -> Data {
    let component = StructuredFieldSerializer.item(components(profile)[0])
    return Data(
      "\(component): \(field.serialized)\n\"@signature-params\": \(signatureParameters)".utf8)
  }

  /// Checks the signature tagged with `profile` and returns the field it
  /// covers.
  private static func verify(
    _ response: SpaceMACResponse, profile: SpaceMACProfile, encapsulation: SpaceKeyEncapsulation
  ) throws -> StructuredDictionary {
    guard let inputValue = response.signatureInput, let signatureValue = response.signature,
      let fieldValue = response.coveredField
    else { throw SpaceMACError.missingHeader }
    guard let inputs = StructuredDictionary.parse(inputValue),
      let signatures = StructuredDictionary.parse(signatureValue),
      let field = StructuredDictionary.parse(fieldValue)
    else { throw SpaceMACError.malformedHeader }

    let tagged = tagged(inputs, profile: profile)
    guard tagged.count <= 1 else { throw SpaceMACError.duplicateSignature }
    guard let (label, list) = tagged.first,
      case .item(let signature)? = signatures[label],
      case .bytes(let mac) = signature.bareItem, signature.parameters.isEmpty
    else { throw SpaceMACError.missingSignature }
    guard list.items == components(profile) else { throw SpaceMACError.unexpectedComponents }
    try checkAlgorithm(list.parameters)
    if let keyID = list.parameters["keyid"], keyID != .string(encapsulation.keyShare) {
      throw SpaceMACError.keyIDMismatch
    }

    // The `sf` flag signs the field as re-serialized from its parsed form.
    let base = signatureBase(
      profile: profile, field: field,
      signatureParameters: StructuredFieldSerializer.innerList(list))
    guard HMAC<SHA256>.isValidAuthenticationCode(mac, authenticating: base, using: encapsulation.sharedSecret)
    else { throw SpaceMACError.macMismatch }
    return field
  }

  private static func responseFields(
    _ members: [(key: String, value: StructuredBareItem)], profile: SpaceMACProfile,
    request: SpaceMACRequest, sharedSecret: SymmetricKey
  ) throws -> [(name: String, value: String)] {
    guard request.profile == profile else { throw SpaceMACError.profileMismatch }
    for case (_, .string(let value)) in members
    where !value.utf8.allSatisfy({ (0x20...0x7e).contains($0) }) {
      throw SpaceMACError.malformedHeader
    }
    let field = StructuredDictionary(
      .init(members.map { (key: $0.key, value: StructuredMember.item(StructuredItem($0.value))) }))
    let mac = HMAC<SHA256>.authenticationCode(
      for: signatureBase(
        profile: profile, field: field, signatureParameters: request.signatureParameters),
      using: sharedSecret)
    return [
      (name: profile.coveredFieldName, value: field.serialized),
      (name: signatureInputFieldName, value: "\(request.label)=\(request.signatureParameters)"),
      (name: signatureFieldName, value: "\(request.label)=:\(Data(mac).base64EncodedString()):"),
      (name: "vary", value: acceptSignatureFieldName),
    ]
  }
}

extension StructuredDictionary {
  /// The bare item of the member `key`, or `nil` when it is absent or an
  /// inner list.
  fileprivate func bareItem(_ key: String) -> StructuredBareItem? {
    guard case .item(let item)? = self[key] else { return nil }
    return item.bareItem
  }
}
