import Foundation
import SwiftParser
import Testing

@testable import SwiftAtprotoLex

// Swift warns that a backquoted keyword "does not need to be escaped in
// argument list", which fails a target that treats warnings as errors. The
// generated calls keep the backquotes only on `inout`, the one keyword a call
// label still requires them on, and keep them on the values they pass.
@Suite("Keyword argument labels in generated calls")
struct KeywordArgumentLabelGenerationTests {
  private static let objectFixture = """
    {
      "lexicon": 1,
      "id": "com.example.keywords",
      "defs": {
        "main": {
          "type": "object",
          "required": ["default"],
          "properties": {
            "default": {"type": "integer", "minimum": 1},
            "inout": {"type": "string", "maxLength": 10}
          }
        }
      }
    }
    """

  private static let queryFixture = """
    {
      "lexicon": 1,
      "id": "com.example.keywordQuery",
      "defs": {
        "main": {
          "type": "query",
          "parameters": {
            "type": "params",
            "properties": {
              "default": {"type": "integer", "maximum": 100}
            }
          },
          "output": {
            "encoding": "application/json",
            "schema": {"type": "object", "properties": {}}
          }
        }
      }
    }
    """

  private func generate(withServer: Bool = false) async throws -> (client: String, server: String?) {
    let root = FileManager.default.temporaryDirectory
      .appending(path: "swift-atproto-keyword-labels-\(UUID().uuidString)", directoryHint: .isDirectory)
    defer { try? FileManager.default.removeItem(at: root) }

    let input = root.appending(path: "input", directoryHint: .isDirectory)
    let output = root.appending(path: "output", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: input, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
    try Self.objectFixture.write(to: input.appending(path: "keywords.json"), atomically: true, encoding: .utf8)
    try Self.queryFixture.write(to: input.appending(path: "keywordQuery.json"), atomically: true, encoding: .utf8)

    if withServer {
      try await SwiftAtprotoLex.main(outdir: output, path: input.path, generate: [.client, .server], pluginSource: .command)
    } else {
      try await SwiftAtprotoLex.main(outdir: output, path: input.path, generate: .client, pluginSource: .command)
    }

    let client = try String(contentsOf: output.appending(path: "XRPCAPIClient.swift"), encoding: .utf8)
    let serverURL = output.appending(path: "XRPCAPIProtocol.swift")
    let server = FileManager.default.fileExists(atPath: serverURL.path) ? try String(contentsOf: serverURL, encoding: .utf8) : nil
    return (client, server)
  }

  @Test("object calls leave keyword labels unescaped except inout")
  func objectCalls() async throws {
    let client = try await generate().client
    #expect(!Parser.parse(source: client).hasError)

    let arguments = "default: `default`, `inout`: `inout`, _unknownValues: _unknownValues)"
    // The rebuilt value in `make`, the permissive decode, and the strict decode.
    #expect(client.contains("return Self.init(\(arguments)"))
    #expect(client.contains("self = Self.init(\(arguments)"))
    #expect(client.contains("self = try Self.make(\(arguments)"))
    #expect(!client.contains("`default`: `default`"))
  }

  @Test("query parameter calls leave keyword labels unescaped")
  func queryCalls() async throws {
    let client = try await generate().client
    #expect(!Parser.parse(source: client).hasError)

    // `Input.Query.make` rebuilding the value, and the client method calling it.
    #expect(client.contains("return Self.init(default: `default`)"))
    #expect(client.contains("Input.Query.make(default: `default`)"))
    #expect(!client.contains("`default`: `default`"))
  }

  @Test("server calls leave keyword labels unescaped")
  func serverCalls() async throws {
    let server = try #require(try await generate(withServer: true).server)
    #expect(!Parser.parse(source: server).hasError)

    #expect(server.contains("Input.Query.make(default: query0)"))
    #expect(!server.contains("`default`:"))
  }
}
