import Foundation
import SwiftParser
import Testing

@testable import SwiftAtprotoLex

@Suite("Unknown encoding generation")
struct UnknownEncodingGenerationTests {
  @Test("preserves an unknown encoding as an opaque string")
  func preservesUnknownEncoding() throws {
    let rawValue = "application/x-example; profile=custom"
    let data = try JSONEncoder().encode(rawValue)
    let encoding = try JSONDecoder().decode(EncodingType.self, from: data)

    #expect(encoding == .other(rawValue))
    #expect(try JSONDecoder().decode(String.self, from: JSONEncoder().encode(encoding)) == rawValue)
  }

  @Test("generates a binary procedure input for an unknown encoding")
  func generatesBinaryInputForUnknownEncoding() async throws {
    let root = FileManager.default.temporaryDirectory
      .appending(path: "swift-atproto-unknown-encoding-\(UUID().uuidString)", directoryHint: .isDirectory)
    defer { try? FileManager.default.removeItem(at: root) }

    let input = root.appending(path: "input", directoryHint: .isDirectory)
    let output = root.appending(path: "output", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: input, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

    // app.bsky.video.uploadPart と同じ形。入力が application/octet-stream のため、
    // 以前は "unexpected mimetype" で生成全体が失敗していた。
    let fixture = """
      {
        "lexicon": 1,
        "id": "com.example.uploadPart",
        "defs": {
          "main": {
            "type": "procedure",
            "parameters": {
              "type": "params",
              "required": ["jobId"],
              "properties": {"jobId": {"type": "string"}}
            },
            "input": {"encoding": "application/octet-stream"},
            "output": {
              "encoding": "application/json",
              "schema": {
                "type": "object",
                "required": ["sizeBytes"],
                "properties": {"sizeBytes": {"type": "integer"}}
              }
            }
          }
        }
      }
      """
    try fixture.write(to: input.appending(path: "uploadPart.json"), atomically: true, encoding: .utf8)

    try await SwiftAtprotoLex.main(outdir: output, path: input.path, generate: .client, pluginSource: .command)

    let source = try String(contentsOf: output.appending(path: "XRPCAPIClient.swift"), encoding: .utf8)
    let syntax = Parser.parse(source: source)

    #expect(!syntax.hasError)
    #expect(source.contains(#"static let contentType = "application/octet-stream""#))
    #expect(source.contains("input: Foundation.Data"))
  }
}
