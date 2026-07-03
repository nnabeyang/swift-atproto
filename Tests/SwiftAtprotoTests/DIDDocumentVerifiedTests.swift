import Foundation
import Testing

@testable import SwiftAtproto

struct DIDDocumentVerifiedTests {
  private func makeDoc(id: String, alsoKnownAs: [String]?) -> DIDDocument {
    let akaFragment =
      alsoKnownAs.map { list in
        ", \"alsoKnownAs\": [\(list.map { "\"\($0)\"" }.joined(separator: ", "))]"
      } ?? ""
    let json = """
      {"@context": ["c"], "id": "\(id)"\(akaFragment)}
      """
    return try! JSONDecoder().decode(DIDDocument.self, from: Data(json.utf8))
  }

  @Test
  func unverifiedHandleExtractsBareAtUri() {
    let doc = makeDoc(id: "did:plc:x", alsoKnownAs: ["at://alice.test"])
    #expect(doc.unverifiedHandle?.rawValue == "alice.test")
  }

  @Test
  func unverifiedHandleSkipsDIDAuthority() {
    let doc = makeDoc(id: "did:plc:x", alsoKnownAs: ["at://did:plc:foo", "at://bob.test"])
    #expect(doc.unverifiedHandle?.rawValue == "bob.test")
  }

  @Test
  func unverifiedHandleSkipsCollectionRkey() {
    let doc = makeDoc(
      id: "did:plc:x",
      alsoKnownAs: [
        "at://alice.test/app.bsky.feed.post/abc",
        "at://carol.test",
      ])
    #expect(doc.unverifiedHandle?.rawValue == "carol.test")
  }

  @Test
  func unverifiedHandleNilWhenNoneAdvertised() {
    let doc = makeDoc(id: "did:plc:x", alsoKnownAs: [])
    #expect(doc.unverifiedHandle == nil)
    let noAka = makeDoc(id: "did:plc:x", alsoKnownAs: nil)
    #expect(noAka.unverifiedHandle == nil)
  }

  @Test
  func syncVerifiedSucceedsOnMatch() throws {
    let doc = makeDoc(id: "did:plc:x", alsoKnownAs: ["at://alice.test"])
    let handle = try Handle(string: "alice.test")
    let did = try DID(string: "did:plc:x")
    let v = try doc.verified(expecting: handle, did: did)
    #expect(v.did == did)
    #expect(v.verifiedHandle == handle)
  }

  @Test
  func verifiedCanBeConstructedDirectly() throws {
    let doc = makeDoc(id: "did:plc:x", alsoKnownAs: ["at://alice.test"])
    let did = try DID(string: "did:plc:x")
    let handle = try Handle(string: "alice.test")
    let verified = DIDDocument.Verified(document: doc, did: did, verifiedHandle: handle)
    #expect(verified.document == doc)
    #expect(verified.did == did)
    #expect(verified.verifiedHandle == handle)
  }

  @Test
  func syncVerifiedThrowsHandleMismatch() throws {
    let doc = makeDoc(id: "did:plc:x", alsoKnownAs: ["at://alice.test"])
    let handle = try Handle(string: "eve.test")
    let did = try DID(string: "did:plc:x")
    #expect(throws: DIDDocument.VerifyError.self) {
      try doc.verified(expecting: handle, did: did)
    }
  }

  @Test
  func syncVerifiedThrowsInvalidDIDOnMismatch() throws {
    let doc = makeDoc(id: "did:plc:x", alsoKnownAs: ["at://alice.test"])
    let handle = try Handle(string: "alice.test")
    let wrongDid = try DID(string: "did:plc:y")
    #expect(throws: DIDDocument.VerifyError.self) {
      try doc.verified(expecting: handle, did: wrongDid)
    }
  }

  private struct StubResolver: DIDHandleResolver {
    let map: [String: String]
    func resolveDID(handle: Handle) async throws -> DID {
      guard let raw = map[handle.rawValue] else {
        struct Missing: Error {}
        throw Missing()
      }
      return try DID(string: raw)
    }
  }

  @Test
  func asyncVerifiedRoundTripsOnMatch() async throws {
    let doc = makeDoc(id: "did:plc:x", alsoKnownAs: ["at://alice.test"])
    let resolver = StubResolver(map: ["alice.test": "did:plc:x"])
    let v = try await doc.verified(resolver: resolver)
    #expect(v.did.rawValue == "did:plc:x")
    #expect(v.verifiedHandle.rawValue == "alice.test")
  }

  @Test
  func asyncVerifiedReturnsInvalidOnResolverMismatch() async throws {
    let doc = makeDoc(id: "did:plc:x", alsoKnownAs: ["at://alice.test"])
    let resolver = StubResolver(map: ["alice.test": "did:plc:y"])
    let v = try await doc.verified(resolver: resolver)
    #expect(v.verifiedHandle == .invalid)
    #expect(v.did.rawValue == "did:plc:x")
  }

  @Test
  func asyncVerifiedReturnsInvalidWhenNoHandleAdvertised() async throws {
    let doc = makeDoc(id: "did:plc:x", alsoKnownAs: nil)
    let resolver = StubResolver(map: [:])
    let v = try await doc.verified(resolver: resolver)
    #expect(v.verifiedHandle == .invalid)
    #expect(v.did.rawValue == "did:plc:x")
  }
}
