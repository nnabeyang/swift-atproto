import Foundation
import Testing

@testable import SwiftAtproto

struct DIDDocumentSpaceTests {
  private static let subject = "did:plc:example"

  private func makeDoc(
    services: [DocService] = [],
    verificationMethods: [DocVerificationMethod] = []
  ) -> DIDDocument {
    let encoder = JSONEncoder()
    let json = """
      {
        "@context": ["https://www.w3.org/ns/did/v1"],
        "id": "\(Self.subject)",
        "service": \(try! String(data: encoder.encode(services), encoding: .utf8)!),
        "verificationMethod": \(try! String(data: encoder.encode(verificationMethods), encoding: .utf8)!)
      }
      """
    return try! JSONDecoder().decode(DIDDocument.self, from: Data(json.utf8))
  }

  private func pds(_ endpoint: String = "https://pds.example") -> DocService {
    DocService(id: "#atproto_pds", type: "AtprotoPersonalDataServer", serviceEndpoint: endpoint)
  }

  private func key(id: String, multibase: String) -> DocVerificationMethod {
    DocVerificationMethod(
      id: id,
      type: "Multikey",
      controller: Self.subject,
      publicKeyMultibase: multibase)
  }

  // MARK: - spaceHostUrl

  @Test
  func spaceHostIsThePDS() throws {
    let doc = makeDoc(services: [pds()])
    #expect(try doc.spaceHostUrl == URL(string: "https://pds.example"))
  }

  // The October 1 `#atproto_space_host` entry is ignored, valid or not.
  @Test(arguments: ["https://space.example", "/xrpc", "ftp://space.example"])
  func spaceHostIgnoresTheRetiredEntry(endpoint: String) throws {
    let doc = makeDoc(services: [
      pds(),
      DocService(id: "#atproto_space_host", type: "AtprotoSpaceHost", serviceEndpoint: endpoint),
    ])
    #expect(try doc.spaceHostUrl == URL(string: "https://pds.example"))
  }

  @Test
  func spaceHostThrowsWithoutAPDS() {
    let doc = makeDoc(services: [
      DocService(
        id: "#atproto_space_host", type: "AtprotoSpaceHost",
        serviceEndpoint: "https://space.example")
    ])
    #expect(throws: DIDDocument.VerifyError.self) { try doc.spaceHostUrl }
  }

  // MARK: - spaceSigningKey

  @Test
  func spaceSigningKeyIsTheAccountKey() throws {
    let doc = makeDoc(verificationMethods: [
      key(id: "#atproto", multibase: "zAccount"),
      key(id: "#atproto_space", multibase: "zSpace"),
    ])
    #expect(try doc.spaceSigningKey.publicKeyMultibase == "zAccount")
  }

  @Test
  func spaceSigningKeyAcceptsAbsoluteEntryID() throws {
    let doc = makeDoc(verificationMethods: [
      key(id: "did:plc:example#atproto", multibase: "zAccount")
    ])
    #expect(try doc.spaceSigningKey.publicKeyMultibase == "zAccount")
  }

  @Test
  func spaceSigningKeyIgnoresTheRetiredEntry() {
    let doc = makeDoc(verificationMethods: [key(id: "#atproto_space", multibase: "zSpace")])
    #expect(throws: DIDDocument.VerifyError.self) { try doc.spaceSigningKey }
  }

  // MARK: - spaceSigningKey(keyId:)

  @Test
  func spaceSigningKeyByIDResolvesAccountKey() throws {
    let doc = makeDoc(verificationMethods: [
      key(id: "#atproto", multibase: "zAccount"),
      key(id: "#atproto_space", multibase: "zSpace"),
    ])
    #expect(try doc.spaceSigningKey(keyId: "#atproto").publicKeyMultibase == "zAccount")
  }

  @Test
  func spaceSigningKeyByIDThrowsWhenAbsent() {
    let doc = makeDoc(verificationMethods: [key(id: "#other", multibase: "zOther")])
    #expect(throws: DIDDocument.VerifyError.self) { try doc.spaceSigningKey(keyId: "#atproto") }
  }

  // The `kid` has to be exactly `#atproto`.
  @Test(arguments: ["atproto", "#atproto_space", "atproto_space", "atproto_pds", "verificationKey", "", "#"])
  func spaceSigningKeyByIDRejectsOtherKeyIDs(keyId: String) {
    let doc = makeDoc(verificationMethods: [
      key(id: "#atproto", multibase: "zAccount"),
      key(id: "#atproto_space", multibase: "zSpace"),
    ])
    #expect(throws: DIDDocument.VerifyError.self) { try doc.spaceSigningKey(keyId: keyId) }
  }

  // MARK: - spaceKEMKey

  @Test
  func spaceKEMKeyIsTheDedicatedEntry() throws {
    let doc = makeDoc(verificationMethods: [
      key(id: "#atproto", multibase: "zAccount"),
      key(id: "did:plc:example#atproto_kem", multibase: "zKEM"),
    ])
    #expect(try doc.spaceKEMKey.publicKeyMultibase == "zKEM")
  }

  @Test
  func spaceKEMKeyDoesNotFallBackToTheSigningKey() {
    let doc = makeDoc(verificationMethods: [key(id: "#atproto", multibase: "zAccount")])
    #expect(throws: DIDDocument.VerifyError.self) { try doc.spaceKEMKey }
  }

  // MARK: - spaceHostAudience

  @Test
  func spaceHostAudienceIsThePDSService() {
    #expect(makeDoc().spaceHostAudience == "did:plc:example#atproto_pds")
    let withEntry = makeDoc(services: [
      DocService(
        id: "#atproto_space_host", type: "AtprotoSpaceHost",
        serviceEndpoint: "https://space.example")
    ])
    #expect(withEntry.spaceHostAudience == "did:plc:example#atproto_pds")
  }

  // MARK: - ServiceIdentifier

  @Test
  func serviceIdentifierParsesFragment() throws {
    let id = try ServiceIdentifier(string: "did:web:syncer.example.com#atproto_space_syncer")
    #expect(id.did.rawValue == "did:web:syncer.example.com")
    #expect(id.fragment == "atproto_space_syncer")
    #expect(id.rawValue == "did:web:syncer.example.com#atproto_space_syncer")
  }

  @Test
  func serviceIdentifierParsesBareDID() throws {
    let id = try ServiceIdentifier(string: "did:plc:example")
    #expect(id.did.rawValue == "did:plc:example")
    #expect(id.fragment == nil)
    #expect(id.rawValue == "did:plc:example")
  }

  @Test(arguments: ["did:plc:example#", "did:plc:example#a#b"])
  func serviceIdentifierRejectsMalformedFragment(string: String) {
    #expect(throws: DIDDocument.VerifyError.self) { try ServiceIdentifier(string: string) }
  }

  // An empty DID part is a malformed DID rather than a malformed fragment, so it surfaces as a
  // `LexiconStringFormatError` from the DID parser.
  @Test(arguments: ["not-a-did#frag", "did:PLC:example", "", "#atproto_space_syncer"])
  func serviceIdentifierRejectsMalformedDID(string: String) {
    #expect(throws: LexiconStringFormatError.self) { try ServiceIdentifier(string: string) }
  }

  // MARK: - endpoint(for:)

  @Test
  func endpointResolvesFragmentEntryWithoutTypeConstraint() throws {
    let doc = makeDoc(services: [
      pds(),
      DocService(
        id: "#atproto_space_syncer", type: "Whatever", serviceEndpoint: "https://syncer.example"),
    ])
    let id = try ServiceIdentifier(string: "did:plc:example#atproto_space_syncer")
    #expect(try doc.endpoint(for: id) == URL(string: "https://syncer.example"))
  }

  @Test
  func endpointForBareDIDResolvesThroughPDS() throws {
    let doc = makeDoc(services: [pds()])
    let id = try ServiceIdentifier(string: "did:plc:example")
    #expect(try doc.endpoint(for: id) == URL(string: "https://pds.example"))
  }

  @Test
  func endpointThrowsWhenFragmentEntryMissing() throws {
    let doc = makeDoc(services: [pds()])
    let id = try ServiceIdentifier(string: "did:plc:example#atproto_space_syncer")
    #expect(throws: DIDDocument.VerifyError.self) { try doc.endpoint(for: id) }
  }

  @Test
  func endpointThrowsOnMalformedFragmentEndpoint() throws {
    let doc = makeDoc(services: [
      DocService(id: "#atproto_space_syncer", type: "Whatever", serviceEndpoint: "/notify")
    ])
    let id = try ServiceIdentifier(string: "did:plc:example#atproto_space_syncer")
    #expect(throws: DIDDocument.VerifyError.self) { try doc.endpoint(for: id) }
  }

  // The document must be the one for the identifier's DID; resolving against another account's
  // document would silently address the wrong service.
  @Test
  func endpointThrowsWhenIdentifierNamesAnotherDID() throws {
    let doc = makeDoc(services: [pds()])
    let id = try ServiceIdentifier(string: "did:plc:other#atproto_space_syncer")
    #expect(throws: DIDDocument.VerifyError.self) { try doc.endpoint(for: id) }
  }

  // MARK: - Entry lookup

  @Test
  func lookupsReturnNilWhenArraysAreAbsent() throws {
    let json = """
      {"@context": ["c"], "id": "did:plc:example"}
      """
    let doc = try JSONDecoder().decode(DIDDocument.self, from: Data(json.utf8))
    #expect(doc.serviceEntry(fragment: "atproto_space_host") == nil)
    #expect(doc.verificationMaterial(fragment: "atproto_space") == nil)
  }
}

extension DocService {
  fileprivate init(id: String, type: String, serviceEndpoint: String) {
    let json = """
      {"id": "\(id)", "type": "\(type)", "serviceEndpoint": "\(serviceEndpoint)"}
      """
    self = try! JSONDecoder().decode(DocService.self, from: Data(json.utf8))
  }
}

extension DocVerificationMethod {
  fileprivate init(id: String, type: String, controller: String, publicKeyMultibase: String) {
    let json = """
      {
        "id": "\(id)", "type": "\(type)",
        "controller": "\(controller)", "publicKeyMultibase": "\(publicKeyMultibase)"
      }
      """
    self = try! JSONDecoder().decode(DocVerificationMethod.self, from: Data(json.utf8))
  }
}
