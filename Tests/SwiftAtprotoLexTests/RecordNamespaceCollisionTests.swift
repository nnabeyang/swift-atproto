import Foundation
import SwiftParser
import Testing

@testable import SwiftAtprotoLex

@Suite("Record NSID / namespace enum collision")
struct RecordNamespaceCollisionTests {
  @Test("record whose id doubles as a namespace prefix keeps its name")
  func recordNameCollidingWithNamespaceKeepsName() async throws {
    let root = FileManager.default.temporaryDirectory
      .appending(path: "swift-atproto-record-namespace-collision-\(UUID().uuidString)", directoryHint: .isDirectory)
    defer { try? FileManager.default.removeItem(at: root) }

    let input = root.appending(path: "input", directoryHint: .isDirectory)
    let output = root.appending(path: "output", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: input, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

    let repoFixture = """
      {
        "lexicon": 1,
        "id": "com.example.repo",
        "defs": {
          "main": {
            "type": "record",
            "key": "tid",
            "record": {
              "type": "object",
              "required": ["name"],
              "properties": {"name": {"type": "string"}}
            }
          }
        }
      }
      """
    let issueCommentFixture = """
      {
        "lexicon": 1,
        "id": "com.example.repo.issue.comment",
        "defs": {
          "main": {
            "type": "object",
            "required": ["note"],
            "properties": {"note": {"type": "string"}}
          }
        }
      }
      """
    let issueStateOpenFixture = """
      {
        "lexicon": 1,
        "id": "com.example.repo.issue.state.open",
        "defs": {
          "main": {
            "type": "object",
            "required": ["by"],
            "properties": {"by": {"type": "string"}}
          }
        }
      }
      """
    try repoFixture.write(to: input.appending(path: "repo.json"), atomically: true, encoding: .utf8)
    try issueCommentFixture.write(to: input.appending(path: "issueComment.json"), atomically: true, encoding: .utf8)
    try issueStateOpenFixture.write(to: input.appending(path: "issueStateOpen.json"), atomically: true, encoding: .utf8)

    try await SwiftAtprotoLex.main(outdir: output, path: input.path, generate: .client, pluginSource: .command)

    let source = try String(contentsOf: output.appending(path: "XRPCAPIClient.swift"), encoding: .utf8)
    let syntax = Parser.parse(source: source)

    #expect(!syntax.hasError)
    // Record keeps its natural name — no `_` suffix.
    #expect(source.contains("public struct Repo: ATProtoRecord"))
    #expect(!source.contains("public struct Repo_"))
    // The conflicting namespace enum is omitted.
    #expect(!source.contains("public enum Repo "))
    // The sub-namespace remains available through an extension on the record.
    #expect(source.contains("extension Com.Example.Repo "))
    #expect(source.contains("public enum Issue "))
  }
}
