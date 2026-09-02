import Foundation
import SwiftParser
import Testing

@testable import SwiftAtprotoLex

@Suite("Binary response streaming generation")
struct BinaryResponseStreamingGenerationTests {
  @Test("preserves an unknown encoding as an opaque string")
  func preservesUnknownEncoding() throws {
    let rawValue = "application/x-example; profile=custom"
    let data = try JSONEncoder().encode(rawValue)
    let encoding = try JSONDecoder().decode(EncodingType.self, from: data)

    #expect(encoding == .other(rawValue))
    #expect(try JSONDecoder().decode(String.self, from: JSONEncoder().encode(encoding)) == rawValue)
  }

  @Test("generates streaming overloads only for binary outputs")
  func generatesBinaryStreamingMethods() async throws {
    let source = try await generate([
      "getArchive.json": Self.getArchive,
      "exportVideo.json": Self.exportVideo,
      "getMetadata.json": Self.getMetadata,
    ])

    #expect(!Parser.parse(source: source).hasError)
    #expect(source.contains("XRPCQuery, XRPCBinaryResponseRequest"))
    #expect(source.contains("XRPCProcedure, XRPCBinaryResponseRequest"))
    #expect(source.contains("func GetArchiveStreaming("))
    #expect(source.contains("func ExportVideoStreaming("))
    #expect(source.contains("where Self: XRPCStreamingCallable"))
    #expect(!source.contains("func GetMetadataStreaming("))
  }

  @Test("preserves custom MIME types in clients and streaming server responses")
  func generatesCustomBinaryServerResponse() async throws {
    let source = try await generateServer(["getDiff.json": Self.getDiff])

    #expect(!Parser.parse(source: source).hasError)
    #expect(source.contains("typealias ResponseBody = Foundation.Data"))
    #expect(source.contains("case binary(OpenAPIRuntime.HTTPBody)"))
    #expect(source.contains("try converter.validateAcceptIfPresent(\"text/x-diff; charset=utf-8\", in: request.headerFields)"))
    #expect(source.contains("response.headerFields[.contentType] = \"text/x-diff; charset=utf-8\""))
    #expect(source.contains("guard case .binary(let value) = value.body"))
    #expect(!source.contains("setResponseBodyAsJSON(value"))
  }

  @Test("uses the declared MIME type for unknown procedure inputs")
  func generatesCustomBinaryInput() async throws {
    let source = try await generateServer(["importDiff.json": Self.importDiff])

    #expect(!Parser.parse(source: source).hasError)
    #expect(source.contains("public static let contentType = \"text/x-diff\""))
    #expect(source.contains("typealias RequestBody = Foundation.Data"))
    #expect(source.contains("case binary(HTTPBody)"))
    #expect(source.contains("options: [\"text/x-diff\"]"))
  }

  @Test("streams every non-JSON server response body")
  func generatesNonJSONServerResponses() async throws {
    let source = try await generateServer([
      "exportLines.json": Self.exportLines,
      "exportVideo.json": Self.exportVideo,
      "getArchive.json": Self.getArchive,
      "getText.json": Self.getText,
    ])

    #expect(!Parser.parse(source: source).hasError)
    #expect(source.components(separatedBy: "case binary(OpenAPIRuntime.HTTPBody)").count - 1 == 4)
    #expect(source.components(separatedBy: "guard case .binary(let value) = value.body").count - 1 == 4)
  }

  @Test("keeps application/json on the structured serializer")
  func generatesJSONServerResponse() async throws {
    let source = try await generateServer(["getMetadata.json": Self.getMetadata])

    #expect(!Parser.parse(source: source).hasError)
    #expect(source.contains("case json(ResponseBody)"))
    #expect(source.contains("try converter.setResponseBodyAsJSON("))
    #expect(!source.contains("case binary(OpenAPIRuntime.HTTPBody)"))
  }

  @Test("requires an actual response MIME type for wildcard outputs")
  func generatesWildcardServerResponse() async throws {
    let source = try await generateServer(["getBlob.json": Self.getBlob])

    #expect(!Parser.parse(source: source).hasError)
    #expect(source.contains("case binary(OpenAPIRuntime.HTTPBody, contentType: Swift.String)"))
    #expect(source.contains("guard case .binary(let value, contentType: let contentType) = value.body"))
    #expect(source.contains("try converter.validateAcceptIfPresent(contentType, in: request.headerFields)"))
    #expect(source.contains("response.headerFields[.contentType] = contentType"))
    #expect(!source.contains("response.headerFields[.contentType] = \"*/*\""))
  }

  private func generate(_ fixtures: [String: String]) async throws -> String {
    let root = FileManager.default.temporaryDirectory
      .appending(path: "swift-atproto-streaming-generation-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: root) }
    let input = root.appending(path: "input")
    let output = root.appending(path: "output")
    try FileManager.default.createDirectory(at: input, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
    for (name, fixture) in fixtures {
      try Data(fixture.utf8).write(to: input.appending(path: name))
    }
    try await SwiftAtprotoLex.main(
      outdir: output, path: input.path, generate: .client, pluginSource: .command)
    return try String(contentsOf: output.appending(path: "XRPCAPIClient.swift"), encoding: .utf8)
  }

  private func generateServer(_ fixtures: [String: String]) async throws -> String {
    let root = FileManager.default.temporaryDirectory
      .appending(path: "swift-atproto-binary-server-generation-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: root) }
    let input = root.appending(path: "input")
    let output = root.appending(path: "output")
    try FileManager.default.createDirectory(at: input, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
    for (name, fixture) in fixtures {
      try Data(fixture.utf8).write(to: input.appending(path: name))
    }
    try await SwiftAtprotoLex.main(
      outdir: output, path: input.path, generate: [.client, .server], pluginSource: .command)
    return try FileManager.default.contentsOfDirectory(at: output, includingPropertiesForKeys: nil)
      .filter { $0.pathExtension == "swift" }
      .sorted { $0.lastPathComponent < $1.lastPathComponent }
      .map { try String(contentsOf: $0, encoding: .utf8) }
      .joined(separator: "\n")
  }

  private static let getArchive = """
    {
      "lexicon": 1,
      "id": "app.example.getArchive",
      "defs": {
        "main": {
          "type": "query",
          "parameters": { "type": "params", "properties": {} },
          "output": { "encoding": "application/vnd.ipld.car" }
        }
      }
    }
    """

  private static let exportVideo = """
    {
      "lexicon": 1,
      "id": "app.example.exportVideo",
      "defs": {
        "main": {
          "type": "procedure",
          "output": { "encoding": "video/mp4" }
        }
      }
    }
    """

  private static let getMetadata = """
    {
      "lexicon": 1,
      "id": "app.example.getMetadata",
      "defs": {
        "main": {
          "type": "query",
          "parameters": { "type": "params", "properties": {} },
          "output": {
            "encoding": "application/json",
            "schema": { "type": "object", "properties": {} }
          }
        }
      }
    }
    """

  private static let getDiff = """
    {
      "lexicon": 1,
      "id": "app.example.getDiff",
      "defs": {
        "main": {
          "type": "query",
          "parameters": { "type": "params", "properties": {} },
          "output": { "encoding": "text/x-diff; charset=utf-8" }
        }
      }
    }
    """

  private static let importDiff = """
    {
      "lexicon": 1,
      "id": "app.example.importDiff",
      "defs": {
        "main": {
          "type": "procedure",
          "input": { "encoding": "text/x-diff" },
          "output": {
            "encoding": "application/json",
            "schema": { "type": "object", "properties": {} }
          }
        }
      }
    }
    """

  private static let exportLines = """
    {
      "lexicon": 1,
      "id": "app.example.exportLines",
      "defs": {
        "main": {
          "type": "query",
          "parameters": { "type": "params", "properties": {} },
          "output": { "encoding": "application/jsonl" }
        }
      }
    }
    """

  private static let getText = """
    {
      "lexicon": 1,
      "id": "app.example.getText",
      "defs": {
        "main": {
          "type": "query",
          "parameters": { "type": "params", "properties": {} },
          "output": { "encoding": "text/plain" }
        }
      }
    }
    """

  private static let getBlob = """
    {
      "lexicon": 1,
      "id": "app.example.getBlob",
      "defs": {
        "main": {
          "type": "query",
          "parameters": { "type": "params", "properties": {} },
          "output": { "encoding": "*/*" }
        }
      }
    }
    """
}
