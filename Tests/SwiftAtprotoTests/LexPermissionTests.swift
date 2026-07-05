import Foundation
import Testing

@testable import SwiftAtproto

struct LexPermissionTests {
  @Test func resourceKnownConstantsRoundTrip() throws {
    let encoder = JSONEncoder()
    let decoder = JSONDecoder()
    for value in [LexPermissionResource.rpc, .repo] {
      let data = try encoder.encode(value)
      #expect(String(data: data, encoding: .utf8) == "\"\(value.rawValue)\"")
      let decoded = try decoder.decode(LexPermissionResource.self, from: data)
      #expect(decoded == value)
    }
  }

  @Test func resourcePreservesUnknownRawValue() throws {
    let data = Data("\"blob\"".utf8)
    let decoded = try JSONDecoder().decode(LexPermissionResource.self, from: data)
    #expect(decoded.rawValue == "blob")
    #expect(decoded != .rpc)
    #expect(decoded != .repo)

    let reEncoded = try JSONEncoder().encode(decoded)
    #expect(String(data: reEncoded, encoding: .utf8) == "\"blob\"")
  }

  @Test func actionKnownConstantsRoundTrip() throws {
    let encoder = JSONEncoder()
    let decoder = JSONDecoder()
    for value in [LexPermissionAction.create, .update, .delete] {
      let data = try encoder.encode(value)
      #expect(String(data: data, encoding: .utf8) == "\"\(value.rawValue)\"")
      let decoded = try decoder.decode(LexPermissionAction.self, from: data)
      #expect(decoded == value)
    }
  }

  @Test func actionPreservesUnknownRawValue() throws {
    let data = Data("\"wibble\"".utf8)
    let decoded = try JSONDecoder().decode(LexPermissionAction.self, from: data)
    #expect(decoded.rawValue == "wibble")
    #expect(decoded != .create)
  }

  @Test func permissionRpcDefaultsOmitOptionalsAtInit() {
    let perm = LexPermission(resource: .rpc, inheritAud: true, lxm: ["app.bsky.feed.getTimeline"])
    #expect(perm.resource == .rpc)
    #expect(perm.inheritAud == true)
    #expect(perm.lxm == ["app.bsky.feed.getTimeline"])
    #expect(perm.aud == nil)
    #expect(perm.action == nil)
    #expect(perm.collection == nil)
  }

  @Test func permissionRoundTripPreservesAllFields() throws {
    let original = LexPermission(
      resource: .repo,
      action: [.create, .delete, LexPermissionAction(rawValue: "wibble")],
      collection: ["app.bsky.feed.post"]
    )
    let data = try JSONEncoder().encode(original)
    let decoded = try JSONDecoder().decode(LexPermission.self, from: data)
    #expect(decoded == original)
  }
}
