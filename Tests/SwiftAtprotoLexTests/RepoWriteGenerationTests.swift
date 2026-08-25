import Foundation
import SwiftParser
import Testing

@testable import SwiftAtprotoLex

@Suite("Repository write generation")
struct RepoWriteGenerationTests {
  @Test("applyWrites describes every repository write")
  func applyWritesDescribesEveryRepositoryWrite() async throws {
    let source = try await generateClient(nsid: "com.atproto.repo.applyWrites")

    #expect(!Parser.parse(source: source).hasError)
    #expect(
      source.contains(
        "public struct RepoApplyWrites_Input: Codable, Hashable, Sendable, RepoWriteOperationDescribing"
      ))
    #expect(source.contains("public var repoWriteRequirements: [RepoWriteRequirement]"))
    #expect(source.contains("case .repoApplyWritesCreate(let value):"))
    #expect(
      source.contains(
        "RepoWriteRequirement(collection: value.collection.rawValue, action: .create)"))
    #expect(source.contains("case .repoApplyWritesUpdate(let value):"))
    #expect(
      source.contains(
        "RepoWriteRequirement(collection: value.collection.rawValue, action: .update)"))
    #expect(source.contains("case .repoApplyWritesDelete(let value):"))
    #expect(
      source.contains(
        "RepoWriteRequirement(collection: value.collection.rawValue, action: .delete)"))
    #expect(source.contains("case ._other(let value):"))
    #expect(source.contains("action: LexPermissionAction(rawValue: \"unsupported\")"))
  }

  @Test("similarly named procedures do not receive repository write guards")
  func similarlyNamedProceduresDoNotReceiveRepositoryWriteGuards() async throws {
    let source = try await generateClient(nsid: "com.atproto.space.applyWrites")

    #expect(!Parser.parse(source: source).hasError)
    #expect(!source.contains("RepoWriteOperationDescribing"))
    #expect(!source.contains("repoWriteRequirements"))
  }

  private func generateClient(nsid: String) async throws -> String {
    let root = FileManager.default.temporaryDirectory
      .appending(path: "swift-atproto-repo-write-generation-\(UUID().uuidString)", directoryHint: .isDirectory)
    defer { try? FileManager.default.removeItem(at: root) }

    let input = root.appending(path: "input", directoryHint: .isDirectory)
    let output = root.appending(path: "output", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: input, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
    try fixture(nsid: nsid).write(
      to: input.appending(path: "applyWrites.json"), atomically: true, encoding: .utf8)

    try await SwiftAtprotoLex.main(
      outdir: output, path: input.path, generate: .client, pluginSource: .command)
    return try String(
      contentsOf: output.appending(path: "XRPCAPIClient.swift"), encoding: .utf8)
  }

  private func fixture(nsid: String) -> String {
    """
    {
      "lexicon": 1,
      "id": "\(nsid)",
      "defs": {
        "main": {
          "type": "procedure",
          "input": {
            "encoding": "application/json",
            "schema": {
              "type": "object",
              "required": ["repo", "writes"],
              "properties": {
                "repo": {"type": "string", "format": "at-identifier"},
                "writes": {
                  "type": "array",
                  "items": {
                    "type": "union",
                    "refs": ["#create", "#update", "#delete"],
                    "closed": true
                  }
                }
              }
            }
          }
        },
        "create": {
          "type": "object",
          "required": ["collection", "value"],
          "properties": {
            "collection": {"type": "string", "format": "nsid"},
            "value": {"type": "unknown"}
          }
        },
        "update": {
          "type": "object",
          "required": ["collection", "rkey", "value"],
          "properties": {
            "collection": {"type": "string", "format": "nsid"},
            "rkey": {"type": "string", "format": "record-key"},
            "value": {"type": "unknown"}
          }
        },
        "delete": {
          "type": "object",
          "required": ["collection", "rkey"],
          "properties": {
            "collection": {"type": "string", "format": "nsid"},
            "rkey": {"type": "string", "format": "record-key"}
          }
        }
      }
    }
    """
  }
}
