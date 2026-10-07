import Foundation
import SwiftParser
import Testing

@testable import SwiftAtprotoLex

// Checks the generated server against the XRPC contract every PDS relies on
// (https://atproto.com/specs/xrpc), using trimmed copies of common
// com.atproto lexicons rather than anything specific to one service.
@Suite("XRPC server contract generation")
struct XRPCServerContractTests {
  private func generateServer() async throws -> String {
    let root = FileManager.default.temporaryDirectory
      .appending(path: "swift-atproto-xrpc-server-contract-\(UUID().uuidString)", directoryHint: .isDirectory)
    defer { try? FileManager.default.removeItem(at: root) }

    let input = root.appending(path: "input", directoryHint: .isDirectory)
    let output = root.appending(path: "output", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: input, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

    for (name, contents) in fixtures {
      try contents.write(to: input.appending(path: name), atomically: true, encoding: .utf8)
    }

    try await SwiftAtprotoLex.main(
      outdir: output,
      path: input.path,
      generate: [.client, .server],
      pluginSource: .command)
    return try String(contentsOf: output.appending(path: "XRPCAPIProtocol.swift"), encoding: .utf8)
  }

  private var fixtures: [String: String] {
    [
      "listRecords.json": """
      {
        "lexicon": 1,
        "id": "com.atproto.repo.listRecords",
        "defs": {
          "main": {
            "type": "query",
            "parameters": {
              "type": "params",
              "required": ["repo", "collection"],
              "properties": {
                "repo": {"type": "string", "format": "at-identifier"},
                "collection": {"type": "string", "format": "nsid"},
                "limit": {"type": "integer", "minimum": 1, "maximum": 100, "default": 50},
                "cursor": {"type": "string"},
                "reverse": {"type": "boolean"}
              }
            },
            "output": {
              "encoding": "application/json",
              "schema": {"type": "object", "properties": {"cursor": {"type": "string"}}}
            }
          }
        }
      }
      """,
      "getBlocks.json": """
      {
        "lexicon": 1,
        "id": "com.atproto.sync.getBlocks",
        "defs": {
          "main": {
            "type": "query",
            "parameters": {
              "type": "params",
              "required": ["did", "cids"],
              "properties": {
                "did": {"type": "string", "format": "did"},
                "cids": {"type": "array", "items": {"type": "string", "format": "cid"}}
              }
            },
            "output": {"encoding": "application/vnd.ipld.car"}
          }
        }
      }
      """,
      "createRecord.json": """
      {
        "lexicon": 1,
        "id": "com.atproto.repo.createRecord",
        "defs": {
          "main": {
            "type": "procedure",
            "input": {
              "encoding": "application/json",
              "schema": {
                "type": "object",
                "required": ["repo", "collection", "record"],
                "properties": {
                  "repo": {"type": "string", "format": "at-identifier"},
                  "collection": {"type": "string", "format": "nsid"},
                  "record": {"type": "unknown"}
                }
              }
            },
            "output": {
              "encoding": "application/json",
              "schema": {
                "type": "object",
                "required": ["uri", "cid"],
                "properties": {
                  "uri": {"type": "string", "format": "at-uri"},
                  "cid": {"type": "string", "format": "cid"}
                }
              }
            }
          }
        }
      }
      """,
    ]
  }

  // XRPC answers a successful query or procedure with 200 OK. Both share one
  // serializer, so a single status literal covers every operation.
  @Test("answers success with 200 for queries and procedures")
  func successStatusIs200() async throws {
    let source = try await generateServer()

    #expect(!Parser.parse(source: source).hasError)
    #expect(source.contains("soar_statusCode: 200"))
    #expect(!source.contains("soar_statusCode: 201"))
  }
}
