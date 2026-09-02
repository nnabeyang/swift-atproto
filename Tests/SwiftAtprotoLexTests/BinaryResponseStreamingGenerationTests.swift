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
}
