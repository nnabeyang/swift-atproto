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
  func spaceHostUsesDedicatedEntry() throws {
    let doc = makeDoc(services: [
      pds(),
      DocService(
        id: "#atproto_space_host", type: "AtprotoSpaceHost",
        serviceEndpoint: "https://space.example"),
    ])
    #expect(try doc.spaceHostUrl == URL(string: "https://space.example"))
  }

  @Test
  func spaceHostAcceptsAbsoluteEntryID() throws {
    let doc = makeDoc(services: [
      pds(),
      DocService(
        id: "did:plc:example#atproto_space_host", type: "AtprotoSpaceHost",
        serviceEndpoint: "https://space.example"),
    ])
    #expect(try doc.spaceHostUrl == URL(string: "https://space.example"))
  }

  // No service `type` is defined for the space host, so the entry is matched on id alone.
  @Test
  func spaceHostIgnoresServiceType() throws {
    let doc = makeDoc(services: [
      DocService(
        id: "#atproto_space_host", type: "SomethingElse",
        serviceEndpoint: "https://space.example")
    ])
    #expect(try doc.spaceHostUrl == URL(string: "https://space.example"))
  }

  @Test
  func spaceHostFallsBackToPDSWhenAbsent() throws {
    let doc = makeDoc(services: [pds()])
    #expect(try doc.spaceHostUrl == URL(string: "https://pds.example"))
  }

  @Test
  func spaceHostMayPointAtTheSameEndpointAsPDS() throws {
    let doc = makeDoc(services: [
      pds(),
      DocService(
        id: "#atproto_space_host", type: "AtprotoSpaceHost",
        serviceEndpoint: "https://pds.example"),
    ])
    #expect(try doc.spaceHostUrl == URL(string: "https://pds.example"))
  }

  // A published-but-malformed entry is a misconfiguration, not an absent entry: it must not fall
  // through to the PDS.
  @Test
  func spaceHostWithRelativeEndpointThrows() {
    let doc = makeDoc(services: [
      pds(),
      DocService(id: "#atproto_space_host", type: "AtprotoSpaceHost", serviceEndpoint: "/xrpc"),
    ])
    #expect(throws: DIDDocument.VerifyError.self) { try doc.spaceHostUrl }
  }

  @Test
  func spaceHostWithNonHTTPEndpointThrows() {
    let doc = makeDoc(services: [
      pds(),
      DocService(
        id: "#atproto_space_host", type: "AtprotoSpaceHost",
        serviceEndpoint: "ftp://space.example"),
    ])
    #expect(throws: DIDDocument.VerifyError.self) { try doc.spaceHostUrl }
  }

  @Test
  func spaceHostThrowsWhenNeitherEntryExists() {
    let doc = makeDoc()
    #expect(throws: DIDDocument.VerifyError.self) { try doc.spaceHostUrl }
  }

  // MARK: - spaceSigningKey

  @Test
  func spaceSigningKeyPrefersDedicatedEntry() throws {
    let doc = makeDoc(verificationMethods: [
      key(id: "#atproto", multibase: "zAccount"),
      key(id: "#atproto_space", multibase: "zSpace"),
    ])
    #expect(try doc.spaceSigningKey.publicKeyMultibase == "zSpace")
  }

  @Test
  func spaceSigningKeyFallsBackToAccountKey() throws {
    let doc = makeDoc(verificationMethods: [key(id: "#atproto", multibase: "zAccount")])
    #expect(try doc.spaceSigningKey.publicKeyMultibase == "zAccount")
  }

  @Test
  func spaceSigningKeyAcceptsAbsoluteEntryID() throws {
    let doc = makeDoc(verificationMethods: [
      key(id: "did:plc:example#atproto_space", multibase: "zSpace")
    ])
    #expect(try doc.spaceSigningKey.publicKeyMultibase == "zSpace")
  }

  @Test
  func spaceSigningKeyThrowsWhenNeitherEntryExists() {
    let doc = makeDoc(verificationMethods: [key(id: "#other", multibase: "zOther")])
    #expect(throws: DIDDocument.VerifyError.self) { try doc.spaceSigningKey }
  }

  // MARK: - spaceSigningKey(keyId:)

  @Test(arguments: ["atproto", "#atproto"])
  func spaceSigningKeyByIDResolvesAccountKey(keyId: String) throws {
    let doc = makeDoc(verificationMethods: [
      key(id: "#atproto", multibase: "zAccount"),
      key(id: "#atproto_space", multibase: "zSpace"),
    ])
    #expect(try doc.spaceSigningKey(keyId: keyId).publicKeyMultibase == "zAccount")
  }

  @Test(arguments: ["atproto_space", "#atproto_space"])
  func spaceSigningKeyByIDResolvesSpaceKey(keyId: String) throws {
    let doc = makeDoc(verificationMethods: [
      key(id: "#atproto", multibase: "zAccount"),
      key(id: "#atproto_space", multibase: "zSpace"),
    ])
    #expect(try doc.spaceSigningKey(keyId: keyId).publicKeyMultibase == "zSpace")
  }

  // Unlike the fallback property, a named key that is absent is an error rather than a fallback.
  @Test
  func spaceSigningKeyByIDDoesNotFallBack() {
    let doc = makeDoc(verificationMethods: [key(id: "#atproto", multibase: "zAccount")])
    #expect(throws: DIDDocument.VerifyError.self) {
      try doc.spaceSigningKey(keyId: "atproto_space")
    }
  }

  @Test(arguments: ["atproto_pds", "verificationKey", "", "#"])
  func spaceSigningKeyByIDRejectsUnsupportedKeyID(keyId: String) {
    let doc = makeDoc(verificationMethods: [key(id: "#atproto", multibase: "zAccount")])
    #expect(throws: DIDDocument.VerifyError.self) { try doc.spaceSigningKey(keyId: keyId) }
  }

  // MARK: - spaceHostAudience

  @Test
  func spaceHostAudienceIsIndependentOfPublishedEntries() {
    #expect(makeDoc().spaceHostAudience == "did:plc:example#atproto_space_host")
    let withEntry = makeDoc(services: [
      DocService(
        id: "#atproto_space_host", type: "AtprotoSpaceHost",
        serviceEndpoint: "https://space.example")
    ])
    #expect(withEntry.spaceHostAudience == "did:plc:example#atproto_space_host")
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
