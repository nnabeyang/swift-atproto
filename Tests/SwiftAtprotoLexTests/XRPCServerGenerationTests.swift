import Foundation
import SwiftParser
import Testing

@testable import SwiftAtprotoLex

@Suite("XRPC server generation")
struct XRPCServerGenerationTests {
  @Test("server registration requires a selected operation set and uses successful XRPC status")
  func registrationRequiresSelectedOperations() async throws {
    let root = FileManager.default.temporaryDirectory
      .appending(path: "swift-atproto-xrpc-server-\(UUID().uuidString)", directoryHint: .isDirectory)
    defer { try? FileManager.default.removeItem(at: root) }

    let input = root.appending(path: "input", directoryHint: .isDirectory)
    let output = root.appending(path: "output", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: input, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

    let fixture = """
      {
        "lexicon": 1,
        "id": "com.example.check",
        "defs": {
          "main": {
            "type": "query",
            "parameters": {
              "type": "params",
              "required": ["actor", "labels"],
              "properties": {
                "actor": {"type": "string"},
                "labels": {"type": "array", "items": {"type": "string"}}
              }
            },
            "output": {
              "encoding": "application/json",
              "schema": {"type": "object", "properties": {"ok": {"type": "boolean"}}}
            }
          }
        }
      }
      """
    try fixture.write(to: input.appending(path: "check.json"), atomically: true, encoding: .utf8)

    try await SwiftAtprotoLex.main(
      outdir: output,
      path: input.path,
      generate: [.client, .server],
      pluginSource: .command)

    let source = try String(contentsOf: output.appending(path: "XRPCAPIProtocol.swift"), encoding: .utf8)

    #expect(!Parser.parse(source: source).hasError)
    #expect(source.contains("public enum XRPCOperation: String, Hashable, Sendable, CaseIterable"))
    #expect(source.contains("case comExampleCheck = \"com.example.check\""))
    #expect(source.contains("operations: Set<XRPCOperation>"))
    #expect(source.contains("operations.contains("))
    #expect(source.contains(".comExampleCheck)"))
    #expect(source.contains("validateScalarXRPCQueryParameter(\"actor\", in: request.soar_query)"))
    #expect(!source.contains("validateScalarXRPCQueryParameter(\"labels\", in: request.soar_query)"))
    #expect(source.contains("soar_statusCode: 200"))
    #expect(!source.contains("soar_statusCode: 201"))
  }
}
