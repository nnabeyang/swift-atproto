import Foundation
import Testing

@testable import SwiftAtproto

struct DIDDocumentPDSTests {
  private func makeDoc(services: [DocService]) -> DIDDocument {
    let json = """
      {
        "@context": ["https://www.w3.org/ns/did/v1"],
        "id": "did:plc:example",
        "service": \(try! String(data: JSONEncoder().encode(services), encoding: .utf8)!)
      }
      """
    return try! JSONDecoder().decode(DIDDocument.self, from: Data(json.utf8))
  }

  @Test
  func preferAtprotoPdsIdOverAllOthers() throws {
    let doc = makeDoc(services: [
      DocService(id: "#other", type: "AtprotoPersonalDataServer", serviceEndpoint: "https://other.example"),
      DocService(id: "#atproto_pds", type: "SomethingElse", serviceEndpoint: "https://pds.example"),
    ])
    #expect(try doc.pdsUrl == URL(string: "https://pds.example"))
  }

  @Test
  func fallbackToTypeWhenIdMissing() throws {
    let doc = makeDoc(services: [
      DocService(id: "#legacy", type: "AtprotoPersonalDataServer", serviceEndpoint: "https://legacy.example")
    ])
    #expect(try doc.pdsUrl == URL(string: "https://legacy.example"))
  }

  @Test
  func missingPDSServiceThrows() {
    let doc = makeDoc(services: [
      DocService(id: "#other", type: "OtherService", serviceEndpoint: "https://x.example")
    ])
    #expect(throws: DIDDocument.VerifyError.self) { try doc.pdsUrl }
  }

  @Test
  func emptyServiceArrayThrows() {
    let doc = makeDoc(services: [])
    #expect(throws: DIDDocument.VerifyError.self) { try doc.pdsUrl }
  }

  @Test
  func nilServiceArrayThrows() throws {
    let json = """
      {"@context": ["c"], "id": "did:plc:x"}
      """
    let doc = try JSONDecoder().decode(DIDDocument.self, from: Data(json.utf8))
    #expect(throws: DIDDocument.VerifyError.self) { try doc.pdsUrl }
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
