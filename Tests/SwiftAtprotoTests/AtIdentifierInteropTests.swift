import Foundation
import Testing

@testable import SwiftAtproto

// Wire-shape vectors for the lexicon `at-identifier` string format. Dispatches to DID or Handle
// based on the `did:` prefix.
struct AtIdentifierInteropTests {
  @Test func didPrefixDispatchesToDIDCase() throws {
    let id = try AtIdentifier(string: "did:plc:7iza6de2dwap2sbkpav7c6c6")
    switch id {
    case .did(let d):
      #expect(d.rawValue == "did:plc:7iza6de2dwap2sbkpav7c6c6")
    case .handle:
      Issue.record("expected .did variant")
    }
  }

  @Test func nonDidPrefixDispatchesToHandleCase() throws {
    let id = try AtIdentifier(string: "alice.example.com")
    switch id {
    case .did:
      Issue.record("expected .handle variant")
    case .handle(let h):
      #expect(h.rawValue == "alice.example.com")
    }
  }

  @Test func rawValuePreservesWireForDID() throws {
    let input = "did:web:example.com:path"
    let id = try AtIdentifier(string: input)
    #expect(id.rawValue == input)
  }

  @Test func rawValuePreservesWireForHandle() throws {
    let input = "Alice.Example.Com"
    let id = try AtIdentifier(string: input)
    #expect(id.rawValue == input)
  }

  static let invalidDIDs: [String] = [
    "did:", "did:METHOD:val", "did:method:", "did:method:val%",
  ]

  @Test(arguments: invalidDIDs)
  func invalidDIDThrows(_ input: String) {
    #expect(throws: (any Error).self) { try AtIdentifier(string: input) }
  }

  static let invalidHandles: [String] = [
    "", "alice", "alice.0", "-alice.test", "alice_test",
  ]

  @Test(arguments: invalidHandles)
  func invalidHandleThrows(_ input: String) {
    #expect(throws: (any Error).self) { try AtIdentifier(string: input) }
  }

  @Test func equalityIsByCaseAndRawValue() throws {
    let a = try AtIdentifier(string: "did:plc:abc")
    let b = try AtIdentifier(string: "did:plc:abc")
    let c = try AtIdentifier(string: "alice.test")
    #expect(a == b)
    #expect(a != c)
  }

  @Test func usableInSetDeduplicatesEqualValues() throws {
    let s: Set<AtIdentifier> = [
      try AtIdentifier(string: "did:plc:abc"),
      try AtIdentifier(string: "alice.test"),
      try AtIdentifier(string: "did:plc:abc"),
    ]
    #expect(s.count == 2)
  }
}
