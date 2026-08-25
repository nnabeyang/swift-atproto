import Foundation
import SwiftParser
import Testing

@testable import SwiftAtprotoLex

@Suite("Constraint decoding generation")
struct ConstraintDecodingGenerationTests {
  @Test("constrained models support permissive decoding")
  func constrainedModelsSupportPermissiveDecoding() async throws {
    let root = FileManager.default.temporaryDirectory
      .appending(path: "swift-atproto-constraint-decoding-\(UUID().uuidString)", directoryHint: .isDirectory)
    defer { try? FileManager.default.removeItem(at: root) }

    let input = root.appending(path: "input", directoryHint: .isDirectory)
    let output = root.appending(path: "output", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: input, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

    let fixture = """
      {
        "lexicon": 1,
        "id": "com.example.constrained",
        "defs": {
          "main": {
            "type": "object",
            "required": ["value"],
            "properties": {
              "value": {"type": "string", "maxLength": 10}
            }
          }
        }
      }
      """
    try fixture.write(to: input.appending(path: "constrained.json"), atomically: true, encoding: .utf8)

    try await SwiftAtprotoLex.main(outdir: output, path: input.path, generate: .client, pluginSource: .command)

    let source = try String(contentsOf: output.appending(path: "XRPCAPIClient.swift"), encoding: .utf8)
    let syntax = Parser.parse(source: source)

    #expect(!syntax.hasError)
    #expect(source.contains("if !LexiconDecodingMode.shouldValidateConstraints(in: decoder)"))
    #expect(source.contains("self = Self.init(value: value)"))
    #expect(source.contains("self = try Self.make(value: value)"))
  }

  @Test("internal API generation removes public access modifiers")
  func internalAPIRemovesPublicAccessModifiers() async throws {
    let root = FileManager.default.temporaryDirectory
      .appending(path: "swift-atproto-non-public-api-\(UUID().uuidString)", directoryHint: .isDirectory)
    defer { try? FileManager.default.removeItem(at: root) }

    let input = root.appending(path: "input", directoryHint: .isDirectory)
    let output = root.appending(path: "output", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: input, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

    let fixture = """
      {
        "lexicon": 1,
        "id": "com.example.internal",
        "defs": {
          "main": {
            "type": "object",
            "required": ["value"],
            "properties": {"value": {"type": "string"}}
          }
        }
      }
      """
    try fixture.write(
      to: input.appending(path: "internal.json"), atomically: true, encoding: .utf8)

    try await SwiftAtprotoLex.main(
      outdir: output,
      path: input.path,
      generate: [.client, .server],
      accessModifier: .internal,
      pluginSource: .command)

    let client = try String(
      contentsOf: output.appending(path: "XRPCAPIClient.swift"), encoding: .utf8)
    let unknown = try String(
      contentsOf: output.appending(path: "UnknownATPValue.swift"), encoding: .utf8)
    let server = try String(
      contentsOf: output.appending(path: "XRPCAPIProtocol.swift"), encoding: .utf8)

    #expect(!client.contains("public "))
    #expect(!unknown.contains("public "))
    #expect(!server.contains("public "))
    #expect(!Parser.parse(source: client).hasError)
    #expect(!Parser.parse(source: unknown).hasError)
    #expect(!Parser.parse(source: server).hasError)

    try await SwiftAtprotoLex.main(
      outdir: output,
      path: input.path,
      generate: .client,
      accessModifier: .package,
      pluginSource: .command)
    let packageClient = try String(
      contentsOf: output.appending(path: "XRPCAPIClient.swift"), encoding: .utf8)

    #expect(packageClient.contains("package enum Com"))
    #expect(!packageClient.contains("public "))
    #expect(!Parser.parse(source: packageClient).hasError)
  }
}
