import Testing

@testable import SwiftAtproto

struct DIDMethodTests {
  @Test
  func plcMethodIsKnown() throws {
    let did = try DID(string: "did:plc:7iza6de2dwap2sbkpav7c6c6")
    #expect(did.knownMethod == .plc)
    #expect(did.knownMethod.rawValue == "plc")
  }

  @Test
  func webMethodIsKnown() throws {
    let did = try DID(string: "did:web:example.com")
    #expect(did.knownMethod == .web)
    #expect(did.knownMethod.rawValue == "web")
  }

  // Regression: constructing a DID with an unregistered method must succeed. `KnownMethod` is an
  // open tag, not a validation gate — spec compliance means we cannot reject future methods at
  // parse time.
  @Test
  func unknownMethodStillConstructsAndDispatchesToDefault() throws {
    let did = try DID(string: "did:key:zQ3shokFTS3brHcDQrn82RUDfCZESWL1ZdCEJwekUDPQiYBme")
    #expect(did.knownMethod.rawValue == "key")
    #expect(did.knownMethod != .plc)
    #expect(did.knownMethod != .web)

    let bucket: String
    switch did.knownMethod {
    case .plc: bucket = "plc"
    case .web: bucket = "web"
    default: bucket = "other"
    }
    #expect(bucket == "other")
  }

  @Test
  func knownMethodRawValueRoundTrips() {
    #expect(DID.KnownMethod(rawValue: "plc") == .plc)
    #expect(DID.KnownMethod(rawValue: "web") == .web)
    #expect(DID.KnownMethod(rawValue: "future") == DID.KnownMethod(rawValue: "future"))
    #expect(DID.KnownMethod(rawValue: "future") != .plc)
  }

  @Test
  func knownMethodTracksDIDMethodString() throws {
    let did = try DID(string: "did:example:test")
    #expect(did.knownMethod.rawValue == did.method)
  }
}
