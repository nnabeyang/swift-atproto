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

  // The `UniversalServer` method that registers one operation, from its
  // signature up to the next member.
  private func handler(_ name: String, in source: String) throws -> Substring {
    let start = try #require(source.range(of: "func \(name)(\n    request:"))
    let rest = source[start.upperBound...]
    let end = rest.range(of: "\n  func ")?.lowerBound ?? rest.range(of: "\n  private func ")?.lowerBound ?? rest.endIndex
    return source[start.lowerBound..<end]
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

  // A pair with an empty value, or with no `=` at all, carries no Lexicon value.
  // Every parameter is decoded from the normalized string, so `actor=` leaves a
  // required parameter missing and a bare `name` no longer fails as a 500.
  @Test("decodes every query parameter from the normalized query string")
  func queryParametersSkipEmptyValues() async throws {
    let source = try await generateServer()

    #expect(!Parser.parse(source: source).hasError)
    #expect(source.contains("private func xrpcQueryString(_ query: Swift.Substring?) -> Swift.Substring?"))
    #expect(!source.contains("in: request.soar_query"))

    for name in ["ComAtprotoRepoListRecords", "ComAtprotoSyncGetBlocks"] {
      let handler = try handler(name, in: source)
      #expect(handler.contains("let queryString = xrpcQueryString(request.soar_query)"))
    }
    #expect(try handler("ComAtprotoRepoListRecords", in: source).components(separatedBy: "in: queryString,").count - 1 == 5)
    #expect(try handler("ComAtprotoSyncGetBlocks", in: source).components(separatedBy: "in: queryString,").count - 1 == 2)
    #expect(try !handler("ComAtprotoRepoCreateRecord", in: source).contains("queryString"))
  }

  // A repeated name only means something for an array parameter. The runtime
  // decoder would keep the first value of a repeated scalar and drop the rest,
  // so every scalar is counted before it is decoded.
  @Test("rejects repeated values only for scalar query parameters")
  func scalarQueryParametersRejectRepeatedValues() async throws {
    let source = try await generateServer()

    #expect(!Parser.parse(source: source).hasError)
    #expect(source.contains("private func validateXRPCScalarQueryItem(_ name: Swift.String, in query: Swift.Substring?) throws"))
    #expect(source.contains("as: [Swift.String].self) ?? []"))
    #expect(source.contains("throw Swift.DecodingError.dataCorrupted("))

    let listRecords = try handler("ComAtprotoRepoListRecords", in: source)
    for name in ["collection", "cursor", "limit", "repo", "reverse"] {
      #expect(listRecords.contains("try validateXRPCScalarQueryItem(\"\(name)\", in: queryString)"))
    }

    let getBlocks = try handler("ComAtprotoSyncGetBlocks", in: source)
    #expect(getBlocks.contains("try validateXRPCScalarQueryItem(\"did\", in: queryString)"))
    #expect(!getBlocks.contains("validateXRPCScalarQueryItem(\"cids\""))
  }

  // The runtime decoder reports a missing required scalar, but decodes a
  // missing array as `[]`. A required array is checked once it is decoded.
  @Test("rejects a required array query parameter given no values")
  func requiredArrayQueryParametersRejectMissingValues() async throws {
    let source = try await generateServer()

    #expect(!Parser.parse(source: source).hasError)
    #expect(source.contains("private func validateXRPCRequiredArrayQueryItem(_ name: Swift.String, values: some Swift.Collection) throws"))
    #expect(source.contains("throw Swift.DecodingError.valueNotFound(type(of: values), "))

    let getBlocks = try handler("ComAtprotoSyncGetBlocks", in: source)
    #expect(getBlocks.contains("try validateXRPCRequiredArrayQueryItem(\"cids\", values: query0)"))
    #expect(!getBlocks.contains("validateXRPCRequiredArrayQueryItem(\"did\""))
    #expect(try !handler("ComAtprotoRepoListRecords", in: source).contains("validateXRPCRequiredArrayQueryItem"))
  }
}
