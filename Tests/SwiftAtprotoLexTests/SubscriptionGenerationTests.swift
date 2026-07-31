import Foundation
import SwiftParser
import Testing

@testable import SwiftAtprotoLex

@Suite("Subscription generation")
struct SubscriptionGenerationTests {
  @Test("generates a typed subscription stream")
  func generatesTypedSubscriptionStream() async throws {
    let root = FileManager.default.temporaryDirectory
      .appending(path: "swift-atproto-subscription-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: root) }
    let input = root.appending(path: "input")
    let output = root.appending(path: "output")
    try FileManager.default.createDirectory(at: input, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

    let fixture = """
      {
        "lexicon": 1,
        "id": "com.atproto.sync.subscribeRepos",
        "defs": {
          "main": {
            "type": "subscription",
            "description": "Repository event stream.",
            "parameters": {
              "type": "params",
              "properties": { "cursor": { "type": "integer" } }
            },
            "message": {
              "schema": { "type": "union", "refs": ["#commit", "#info"] }
            },
            "errors": [{ "name": "FutureCursor" }]
          },
          "commit": {
            "type": "object",
            "required": ["seq", "blocks"],
            "properties": {
              "seq": { "type": "integer" },
              "blocks": { "type": "bytes" }
            }
          },
          "info": {
            "type": "object",
            "required": ["name"],
            "properties": { "name": { "type": "string" } }
          }
        }
      }
      """
    let officialLexicon = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
      .deletingLastPathComponent()
      .appending(path: "atproto/lexicons/com/atproto/sync/subscribeRepos.json")
    let fixtureData =
      if FileManager.default.fileExists(atPath: officialLexicon.path) {
        try Data(contentsOf: officialLexicon)
      } else {
        Data(fixture.utf8)
      }
    try fixtureData.write(to: input.appending(path: "subscribeRepos.json"))

    try await SwiftAtprotoLex.main(
      outdir: output, path: input.path, generate: .client, pluginSource: .command)

    let source = try String(
      contentsOf: output.appending(path: "XRPCAPIClient.swift"), encoding: .utf8)
    #expect(!Parser.parse(source: source).hasError)
    #expect(source.contains("public enum SyncSubscribeRepos: XRPCSubscription"))
    #expect(source.contains("public typealias Message = Com.Atproto.SyncSubscribeRepos_Message"))
    #expect(!source.contains("public protocol XRPCCallable: XRPCSubscriptionCallable"))
    #expect(source.contains("atprotoSubscriptionMessageType"))
    #expect(source.contains("\"com.atproto.sync.subscribeRepos#commit\""))
    #expect(source.contains("case futurecursor"))
  }

  @Test("encodes formatted subscription parameters as raw values")
  func encodesFormattedSubscriptionParametersAsRawValues() async throws {
    let root = FileManager.default.temporaryDirectory
      .appending(path: "swift-atproto-subscription-parameters-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: root) }
    let input = root.appending(path: "input")
    let output = root.appending(path: "output")
    try FileManager.default.createDirectory(at: input, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

    let fixture = """
      {
        "lexicon": 1,
        "id": "example.stream.subscribeEvents",
        "defs": {
          "main": {
            "type": "subscription",
            "parameters": {
              "type": "params",
              "required": ["repo"],
              "properties": {
                "repo": { "type": "string", "format": "did" },
                "subjects": {
                  "type": "array",
                  "items": { "type": "string", "format": "at-uri" }
                }
              }
            }
          }
        }
      }
      """
    try Data(fixture.utf8).write(to: input.appending(path: "subscribeEvents.json"))

    try await SwiftAtprotoLex.main(
      outdir: output, path: input.path, generate: .client, pluginSource: .command)

    let source = try String(
      contentsOf: output.appending(path: "XRPCAPIClient.swift"), encoding: .utf8)
    #expect(!Parser.parse(source: source).hasError)
    #expect(source.contains(#""repo": .string(repo.rawValue)"#))
    #expect(source.contains(#""subjects": .array(subjects?.map(\.rawValue))"#))
  }
}
