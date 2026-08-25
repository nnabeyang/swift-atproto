import Foundation
import SwiftParser
import Testing

@testable import SwiftAtprotoLex

@Suite("Open permission generation")
struct PermissionGenerationTests {
  @Test("space permissions generate without consumer-specific request policy")
  func generatesSpacePermissionValues() async throws {
    let source = try await generateClient(fixture: Self.spacePermissionSet)

    #expect(!Parser.parse(source: source).hasError)
    #expect(source.contains("public enum AuthForums: LexPermissionSet"))
    #expect(source.contains("resource: .space"))
    #expect(source.contains(#"spaceType: "com.example.forum""#))
    #expect(source.contains(#"authority: "*""#))
    #expect(source.contains("action: [.read, .create]"))
    #expect(source.contains("manage: [.update]"))
    #expect(source.contains(#""futureFlag": .boolean(true)"#))
    #expect(
      source.contains(
        #""futureValues": .array([.string("one"), .integer(2), .boolean(false)])"#))
    #expect(!source.contains("SpaceScopeRequirement"))
  }

  private func generateClient(fixture: String) async throws -> String {
    let root = FileManager.default.temporaryDirectory
      .appending(path: "swift-atproto-permission-generation-\(UUID().uuidString)", directoryHint: .isDirectory)
    defer { try? FileManager.default.removeItem(at: root) }

    let input = root.appending(path: "input", directoryHint: .isDirectory)
    let output = root.appending(path: "output", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: input, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
    try fixture.write(
      to: input.appending(path: "authForums.json"), atomically: true, encoding: .utf8)

    try await SwiftAtprotoLex.main(
      outdir: output, path: input.path, generate: .client, pluginSource: .command)
    return try String(
      contentsOf: output.appending(path: "XRPCAPIClient.swift"), encoding: .utf8)
  }

  static let spacePermissionSet = #"""
    {
      "lexicon": 1,
      "id": "com.example.authForums",
      "defs": {
        "main": {
          "type": "permission-set",
          "title": "Example Forums",
          "detail": "Read and post in example forums",
          "permissions": [
            {
              "type": "permission",
              "resource": "space",
              "spaceType": "com.example.forum",
              "authority": "*",
              "collection": ["net.external.thread"],
              "action": ["read", "create"],
              "manage": ["update"],
              "futureFlag": true,
              "futureValues": ["one", 2, false]
            }
          ]
        }
      }
    }
    """#
}
