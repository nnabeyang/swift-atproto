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
    for value in [LexPermissionAction.readSelf, .read, .create, .update, .delete] {
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

  @Test func spacePermissionRoundTripPreservesOpenFields() throws {
    let json = Data(
      #"{"type":"permission","resource":"space","spaceType":"com.example.forum","authority":"*","skey":"default","collection":["net.external.thread"],"action":["read","create"],"manage":["update"],"futureFlag":true,"futureValues":["one",2,false]}"#.utf8
    )

    let permission = try JSONDecoder().decode(LexPermission.self, from: json)
    #expect(permission.resource == .space)
    #expect(permission.spaceType == "com.example.forum")
    #expect(permission.authority == "*")
    #expect(permission.skey == "default")
    #expect(permission.manage == [.update])
    #expect(permission.additionalFields["futureFlag"] == .boolean(true))
    #expect(
      permission.additionalFields["futureValues"]
        == .array([.string("one"), .integer(2), .boolean(false)]))

    let roundTrip = try JSONEncoder().encode(permission)
    let decoded = try JSONDecoder().decode(LexPermission.self, from: roundTrip)
    #expect(decoded == permission)
  }

  @Test func permissionRejectsNestedOpenArrays() {
    let json = Data(
      #"{"type":"permission","resource":"space","futureValues":[["nested"]]}"#.utf8)
    #expect(throws: (any Error).self) {
      try JSONDecoder().decode(LexPermission.self, from: json)
    }
  }

  @Test func conformingTypeSatisfiesProtocol() {
    #expect(SampleAuthPermissionSet.id == "com.example.auth.sample")
    #expect(SampleAuthPermissionSet.title == "Sample")
    #expect(SampleAuthPermissionSet.detail == nil)
    #expect(SampleAuthPermissionSet.permissions.count == 1)
    #expect(SampleAuthPermissionSet.permissions[0].resource == .rpc)
  }
}

private enum SampleAuthPermissionSet: LexPermissionSet {
  static let id = "com.example.auth.sample"
  static let title: String? = "Sample"
  static let detail: String? = nil
  static let permissions: [LexPermission] = [
    LexPermission(resource: .rpc, inheritAud: true, lxm: ["com.example.foo.getThing"])
  ]
}
