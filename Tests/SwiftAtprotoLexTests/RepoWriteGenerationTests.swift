import Foundation
import SwiftParser
import Testing

@testable import SwiftAtprotoLex

@Suite("Repository write generation")
struct RepoWriteGenerationTests {
  @Test("putRecord requires create and update scopes")
  func putRecordRequiresCreateAndUpdateScopes() async throws {
    let root = FileManager.default.temporaryDirectory
      .appending(path: "swift-atproto-put-record-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: root) }
    let input = root.appending(path: "input")
    let output = root.appending(path: "output")
    try FileManager.default.createDirectory(at: input, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

    let fixture = """
      {
        "lexicon": 1,
        "id": "com.atproto.repo.putRecord",
        "defs": {
          "main": {
            "type": "procedure",
            "input": {
              "encoding": "application/json",
              "schema": {
                "type": "object",
                "required": ["repo", "collection", "rkey", "record"],
                "properties": {
                  "repo": { "type": "string", "format": "at-identifier" },
                  "collection": { "type": "string", "format": "nsid" },
                  "rkey": { "type": "string", "format": "record-key" },
                  "record": { "type": "unknown" }
                }
              }
            }
          }
        }
      }
      """
    try Data(fixture.utf8).write(to: input.appending(path: "putRecord.json"))

    try await SwiftAtprotoLex.main(
      outdir: output, path: input.path, generate: .client, pluginSource: .command)

    let source = try String(
      contentsOf: output.appending(path: "XRPCAPIClient.swift"), encoding: .utf8)
    #expect(!Parser.parse(source: source).hasError)
    #expect(
      source.contains(
        "RepoWriteRequirement(collection: collection.rawValue, action: .create)"
      ))
    #expect(
      source.contains(
        "RepoWriteRequirement(collection: collection.rawValue, action: .update)"
      ))
  }

  @Test("applyWrites describes every generated write variant")
  func applyWritesDescribesEveryGeneratedWriteVariant() async throws {
    let root = FileManager.default.temporaryDirectory
      .appending(path: "swift-atproto-repo-writes-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: root) }
    let input = root.appending(path: "input")
    let output = root.appending(path: "output")
    try FileManager.default.createDirectory(at: input, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

    let fixture = """
      {
        "lexicon": 1,
        "id": "com.atproto.repo.applyWrites",
        "defs": {
          "main": {
            "type": "procedure",
            "input": {
              "encoding": "application/json",
              "schema": {
                "type": "object",
                "required": ["repo", "writes"],
                "properties": {
                  "repo": { "type": "string", "format": "at-identifier" },
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
              "collection": { "type": "string", "format": "nsid" },
              "value": { "type": "unknown" }
            }
          },
          "update": {
            "type": "object",
            "required": ["collection", "rkey", "value"],
            "properties": {
              "collection": { "type": "string", "format": "nsid" },
              "rkey": { "type": "string", "format": "record-key" },
              "value": { "type": "unknown" }
            }
          },
          "delete": {
            "type": "object",
            "required": ["collection", "rkey"],
            "properties": {
              "collection": { "type": "string", "format": "nsid" },
              "rkey": { "type": "string", "format": "record-key" }
            }
          }
        }
      }
      """
    try Data(fixture.utf8).write(to: input.appending(path: "applyWrites.json"))

    try await SwiftAtprotoLex.main(
      outdir: output, path: input.path, generate: .client, pluginSource: .command)

    let source = try String(
      contentsOf: output.appending(path: "XRPCAPIClient.swift"), encoding: .utf8)
    #expect(!Parser.parse(source: source).hasError)
    #expect(
      source.contains(
        "public struct RepoApplyWrites_Input: Codable, Hashable, Sendable, RepoWriteOperationDescribing"
      ))
    #expect(source.contains("case .repoApplyWritesCreate(let value):"))
    #expect(source.contains("case .repoApplyWritesUpdate(let value):"))
    #expect(source.contains("case .repoApplyWritesDelete(let value):"))
    #expect(source.contains("action: .create"))
    #expect(source.contains("action: .update"))
    #expect(source.contains("action: .delete"))
  }
}
