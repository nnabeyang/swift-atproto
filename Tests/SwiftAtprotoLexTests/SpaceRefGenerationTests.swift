import Foundation
import SwiftParser
import Testing

@testable import SwiftAtprotoLex

@Suite("space-ref generation")
struct SpaceRefGenerationTests {
  @Test("space-ref fields generate as FormatString<SpaceRef>")
  func spaceRefFieldsGenerateAsFormatString() async throws {
    let root = FileManager.default.temporaryDirectory
      .appending(path: "swift-atproto-space-ref-\(UUID().uuidString)", directoryHint: .isDirectory)
    defer { try? FileManager.default.removeItem(at: root) }

    let input = root.appending(path: "input", directoryHint: .isDirectory)
    let output = root.appending(path: "output", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: input, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

    // Shaped after `com.atproto.simplespace.getSpace`, which takes the space ref as a query
    // parameter and returns it in the response body.
    let fixture = """
      {
        "lexicon": 1,
        "id": "com.example.getSpace",
        "defs": {
          "main": {
            "type": "query",
            "parameters": {
              "type": "params",
              "required": ["space"],
              "properties": {
                "space": {"type": "string", "format": "space-ref"}
              }
            },
            "output": {
              "encoding": "application/json",
              "schema": {
                "type": "object",
                "required": ["space"],
                "properties": {
                  "space": {"type": "string", "format": "space-ref"},
                  "unknownFormat": {"type": "string", "format": "not-a-real-format"}
                }
              }
            }
          }
        }
      }
      """
    try fixture.write(to: input.appending(path: "getSpace.json"), atomically: true, encoding: .utf8)

    try await SwiftAtprotoLex.main(
      outdir: output,
      path: input.path,
      generate: [.client, .server],
      pluginSource: .command
    )

    let clientSource = try String(contentsOf: output.appending(path: "XRPCAPIClient.swift"), encoding: .utf8)
    let serverSource = try String(contentsOf: output.appending(path: "XRPCAPIProtocol.swift"), encoding: .utf8)

    #expect(!Parser.parse(source: clientSource).hasError)
    #expect(!Parser.parse(source: serverSource).hasError)
    #expect(clientSource.contains("FormatString<SpaceRef>"))
    #expect(serverSource.contains("FormatString<SpaceRef>"))
    // An unrecognized format still falls back to a plain string.
    #expect(clientSource.contains("Swift.String"))
    #expect(!clientSource.contains("FormatString<not-a-real-format>"))
  }
}
