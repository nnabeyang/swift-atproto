import Foundation
import SwiftParser
import Testing

@testable import SwiftAtprotoLex

// `const` fixes a field to one value and a blob's `accept` lists the MIME types
// it may have. Both get constants and are checked wherever the other limits
// are, through the same `make`.
@Suite("const and accept constraints")
struct ConstAcceptConstraintTests {
  private static let fixtures: [String: String] = [
    "post.json": """
    {"lexicon": 1, "id": "com.example.post", "defs": {
      "main": {"type": "object", "required": ["notFound"], "properties": {
        "notFound": {"type": "boolean", "const": true},
        "kind": {"type": "string", "const": "post"},
        "mode": {"type": "string", "const": "fast", "knownValues": ["fast", "slow"]},
        "version": {"type": "integer", "const": 2},
        "video": {"type": "blob", "accept": ["video/mp4"], "maxSize": 1000},
        "images": {"type": "array", "items": {"type": "blob", "accept": ["image/png", "image/jpeg"]}},
        "anything": {"type": "blob", "accept": []}
      }}
    }}
    """,
    "search.json": """
    {"lexicon": 1, "id": "com.example.search", "defs": {"main": {"type": "query",
      "parameters": {"type": "params", "properties": {"sort": {"type": "string", "const": "latest"}}},
      "output": {"encoding": "application/json", "schema": {"type": "object", "properties": {}}}}}}
    """,
  ]

  private func generate() async throws -> String {
    let root = FileManager.default.temporaryDirectory
      .appending(path: "swift-atproto-const-accept-\(UUID().uuidString)", directoryHint: .isDirectory)
    defer { try? FileManager.default.removeItem(at: root) }

    let input = root.appending(path: "input", directoryHint: .isDirectory)
    let output = root.appending(path: "output", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: input, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
    for (name, contents) in Self.fixtures {
      try contents.write(to: input.appending(path: name), atomically: true, encoding: .utf8)
    }

    try await SwiftAtprotoLex.main(outdir: output, path: input.path, generate: .client, pluginSource: .command)
    return try String(contentsOf: output.appending(path: "XRPCAPIClient.swift"), encoding: .utf8)
  }

  /// The lines of `source` with their indentation removed.
  private func lines(_ source: String) -> [String] {
    source.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
  }

  @Test("the generated source parses")
  func parses() async throws {
    #expect(!Parser.parse(source: try await generate()).hasError)
  }

  @Test("const and accept get constants of their own types")
  func constants() async throws {
    let client = lines(try await generate())
    #expect(client.contains("public static let notFoundConst: Swift.Bool = true"))
    #expect(client.contains(#"public static let kindConst: Swift.String = "post""#))
    #expect(client.contains(#"public static let modeConst: Swift.String = "fast""#))
    #expect(client.contains("public static let versionConst: Swift.Int = 2"))
    #expect(client.contains(#"public static let videoAccept: [Swift.String] = ["video/mp4"]"#))
    #expect(client.contains(#"public static let imagesItemAccept: [Swift.String] = ["image/png", "image/jpeg"]"#))
    #expect(client.contains("/// The `accept` of `video` in the Lexicon."))
    // An empty accept restricts nothing, so it gets no constant.
    #expect(!client.contains { $0.contains("anythingAccept") })
  }

  @Test("const compares the value and reports the expected one")
  func constGuards() async throws {
    let client = lines(try await generate())
    #expect(client.contains("guard notFound == Constraints.notFoundConst else {"))
    #expect(
      client.contains(
        #"throw SwiftAtproto.LexiconConstraintError.notConstant("notFound", expected: "\(Constraints.notFoundConst)")"#))
    #expect(client.contains("guard kind == Constraints.kindConst else {"))
    // A string with knownValues has a type of its own.
    #expect(client.contains("guard mode.rawValue == Constraints.modeConst else {"))
    #expect(client.contains("guard version == Constraints.versionConst else {"))
  }

  @Test("accept checks the blob's MIME type through the runtime")
  func acceptGuards() async throws {
    let client = lines(try await generate())
    #expect(client.contains("guard SwiftAtproto.LexBlob.isAccepted(mimeType: video.mimeType, by: Constraints.videoAccept) else {"))
    #expect(
      client.contains(
        #"throw SwiftAtproto.LexiconConstraintError.blobTypeNotAccepted("video", accepted: Constraints.videoAccept)"#))
    #expect(client.contains("for (index, element) in images.enumerated() {"))
    #expect(client.contains("guard SwiftAtproto.LexBlob.isAccepted(mimeType: element.mimeType, by: Constraints.imagesItemAccept) else {"))
    #expect(
      client.contains(
        #"throw SwiftAtproto.LexiconConstraintError.blobTypeNotAccepted("images[\(index)]", accepted: Constraints.imagesItemAccept)"#
      ))
  }

  @Test("query parameters check their const")
  func queryParameters() async throws {
    let client = lines(try await generate())
    #expect(client.contains(#"public static let sortConst: Swift.String = "latest""#))
    #expect(client.contains("guard sort == Constraints.sortConst else {"))
  }
}
