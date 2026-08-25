import Foundation
import SwiftParser
import Testing

@testable import SwiftAtprotoLex

@Suite("Permissioned repository sync generation")
struct PermissionedRepoSyncGenerationTests {
  @Test("signed commits and operations expose sync descriptors")
  func generatesSyncDescriptors() async throws {
    let source = try await generate([
      "defs.json": Self.signedCommit,
      "listRepoOps.json": Self.listRepoOps,
    ])

    #expect(!Parser.parse(source: source).hasError)
    #expect(
      source.contains(
        "public struct SpaceDefs_SignedCommit: Codable, Hashable, Sendable, PermissionedRepoSignedCommitDescribing"
      ))
    #expect(source.contains("public var permissionedRepoCommitInputKeyMaterial: Foundation.Data"))
    #expect(
      source.contains(
        "public struct SpaceListRepoOps_OpEntry: Codable, Hashable, Sendable, PermissionedRepoOperationDescribing"
      ))
    #expect(source.contains("public var permissionedRepoOperationPreviousCID: FormatString<LexLink>?"))
  }

  @Test("a similarly named but incompatible definition gets no conformance")
  func rejectsAnIncompatibleShape() async throws {
    let source = try await generate(["defs.json": Self.incompatibleSignedCommit])

    #expect(!Parser.parse(source: source).hasError)
    #expect(!source.contains("PermissionedRepoSignedCommitDescribing"))
    #expect(!source.contains("permissionedRepoCommitVersion"))
  }

  private func generate(_ files: [String: String]) async throws -> String {
    let root = FileManager.default.temporaryDirectory
      .appending(path: "swift-atproto-permissioned-sync-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: root) }
    let input = root.appending(path: "input")
    let output = root.appending(path: "output")
    try FileManager.default.createDirectory(at: input, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
    for (name, source) in files {
      try Data(source.utf8).write(to: input.appending(path: name))
    }

    try await SwiftAtprotoLex.main(
      outdir: output, path: input.path, generate: .client, pluginSource: .command)
    return try String(
      contentsOf: output.appending(path: "XRPCAPIClient.swift"), encoding: .utf8)
  }

  private static let signedCommit = """
    {
      "lexicon": 1,
      "id": "com.atproto.space.defs",
      "defs": {
        "signedCommit": {
          "type": "object",
          "required": ["ver", "hash", "mac", "ikm", "sig", "rev"],
          "properties": {
            "ver": { "type": "integer" },
            "hash": { "type": "bytes" },
            "ikm": { "type": "bytes" },
            "sig": { "type": "bytes" },
            "mac": { "type": "bytes" },
            "rev": { "type": "string", "format": "tid" }
          }
        }
      }
    }
    """

  private static let incompatibleSignedCommit = """
    {
      "lexicon": 1,
      "id": "com.atproto.space.defs",
      "defs": {
        "signedCommit": {
          "type": "object",
          "required": ["ver", "hash", "mac", "ikm", "sig", "rev"],
          "properties": {
            "ver": { "type": "integer" },
            "hash": { "type": "bytes" },
            "ikm": { "type": "bytes" },
            "sig": { "type": "bytes" },
            "mac": { "type": "bytes" },
            "rev": { "type": "string" }
          }
        }
      }
    }
    """

  private static let listRepoOps = """
    {
      "lexicon": 1,
      "id": "com.atproto.space.listRepoOps",
      "defs": {
        "main": {
          "type": "query",
          "parameters": { "type": "params", "properties": {} },
          "output": {
            "encoding": "application/json",
            "schema": { "type": "object", "properties": {} }
          }
        },
        "opEntry": {
          "type": "object",
          "required": ["rev", "collection", "rkey", "cid", "prev"],
          "nullable": ["cid", "prev"],
          "properties": {
            "rev": { "type": "string", "format": "tid" },
            "collection": { "type": "string", "format": "nsid" },
            "rkey": { "type": "string", "format": "record-key" },
            "cid": { "type": "string", "format": "cid" },
            "prev": { "type": "string", "format": "cid" }
          }
        }
      }
    }
    """
}
