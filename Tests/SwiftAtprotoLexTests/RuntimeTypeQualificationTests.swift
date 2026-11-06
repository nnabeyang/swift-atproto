import Foundation
import SwiftParser
import Testing

@testable import SwiftAtprotoLex

// The generated code lives in namespace enums such as `Com.Example`, so an
// unqualified runtime name would resolve to a generated type of the same
// name. Every runtime reference is written as `SwiftAtproto.X`, whichever way
// the generator builds it.
@Suite("Runtime types in generated code")
struct RuntimeTypeQualificationTests {
  private static let fixtures: [String: String] = [
    "post.json": """
    {"lexicon": 1, "id": "com.example.post", "defs": {"main": {"type": "record", "key": "tid", "record": {
      "type": "object", "required": ["text"],
      "properties": {
        "text": {"type": "string", "maxLength": 10},
        "author": {"type": "string", "format": "did"},
        "image": {"type": "blob", "maxSize": 1000},
        "embed": {"type": "union", "refs": ["com.example.anyCodable"]}
      }}}}}
    """,
    "search.json": """
    {"lexicon": 1, "id": "com.example.search", "defs": {"main": {"type": "query",
      "parameters": {"type": "params", "properties": {"q": {"type": "string", "maxLength": 20}}},
      "output": {"encoding": "application/json", "schema": {"type": "object", "properties": {}}}}}}
    """,
    // No input and no output: the method returns the runtime's empty response.
    "ping.json": """
    {"lexicon": 1, "id": "com.example.ping", "defs": {"main": {"type": "procedure"}}}
    """,
    "subscribe.json": """
    {"lexicon": 1, "id": "com.example.subscribe", "defs": {
      "main": {"type": "subscription",
        "parameters": {"type": "params", "properties": {"cursor": {"type": "integer"}}},
        "message": {"schema": {"type": "union", "refs": ["#event"]}}},
      "event": {"type": "object", "required": ["seq"], "properties": {"seq": {"type": "integer"}}}}}
    """,
    // Types named like runtime types, which the unqualified references would
    // have resolved to.
    "anyCodable.json": """
    {"lexicon": 1, "id": "com.example.anyCodable", "defs": {"main": {"type": "object", "properties": {"x": {"type": "string"}}}}}
    """,
    "lexiconValidatable.json": """
    {"lexicon": 1, "id": "com.example.lexiconValidatable", "defs": {"main": {"type": "object", "properties": {"x": {"type": "string"}}}}}
    """,
    "lexiconConstraintError.json": """
    {"lexicon": 1, "id": "com.example.lexiconConstraintError", "defs": {"main": {"type": "object", "properties": {"x": {"type": "string"}}}}}
    """,
    "lexBlob.json": """
    {"lexicon": 1, "id": "com.example.lexBlob", "defs": {"main": {"type": "object", "properties": {"x": {"type": "string"}}}}}
    """,
  ]

  private func generate() async throws -> (client: String, unknown: String) {
    let root = FileManager.default.temporaryDirectory
      .appending(path: "swift-atproto-runtime-qualification-\(UUID().uuidString)", directoryHint: .isDirectory)
    defer { try? FileManager.default.removeItem(at: root) }

    let input = root.appending(path: "input", directoryHint: .isDirectory)
    let output = root.appending(path: "output", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: input, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
    for (name, contents) in Self.fixtures {
      try contents.write(to: input.appending(path: name), atomically: true, encoding: .utf8)
    }

    try await SwiftAtprotoLex.main(outdir: output, path: input.path, generate: .client, pluginSource: .command)
    return (
      try String(contentsOf: output.appending(path: "XRPCAPIClient.swift"), encoding: .utf8),
      try String(contentsOf: output.appending(path: "UnknownATPValue.swift"), encoding: .utf8)
    )
  }

  @Test("the generated sources parse, with types named like runtime types")
  func parses() async throws {
    let generated = try await generate()
    #expect(!Parser.parse(source: generated.client).hasError)
    #expect(!Parser.parse(source: generated.unknown).hasError)
    // The look-alikes are generated next to the references to the real types.
    #expect(generated.client.contains("public struct AnyCodable: "))
    #expect(generated.client.contains("public struct LexiconValidatable: "))
  }

  @Test("type names built from strings are qualified")
  func typeNameStrings() async throws {
    let client = try await generate().client
    #expect(client.contains("public let author: SwiftAtproto.FormatString<SwiftAtproto.DID>?"))
    #expect(client.contains("public let image: SwiftAtproto.LexBlob?"))
    #expect(client.contains("SwiftAtproto.FormatString<SwiftAtproto.DID>.self"))
    #expect(client.contains("SwiftAtproto.EmptyResponse"))
    #expect(!client.contains(" EmptyResponse"))
  }

  @Test("conformance lists are qualified")
  func conformances() async throws {
    let generated = try await generate()
    #expect(generated.client.contains("public struct Post: SwiftAtproto.ATProtoRecord"))
    #expect(generated.client.contains("Codable, Hashable, Sendable, SwiftAtproto.LexiconValidatable {"))
    #expect(generated.client.contains(": SwiftAtproto.XRPCQuery {"))
    #expect(generated.client.contains("public struct Input: SwiftAtproto.XRPCQueryInput {"))
    #expect(generated.client.contains("public enum Error: SwiftAtproto.XRPCError {"))
    #expect(generated.unknown.contains("UnknownATPValue: SwiftAtproto.UnknownATPValueProtocol, SwiftAtproto.LexiconValidatable {"))
  }

  @Test("references built as syntax nodes are qualified")
  func syntaxNodes() async throws {
    let client = try await generate().client
    #expect(client.contains("public let _unknownValues: [Swift.String: SwiftAtproto.AnyCodable]"))
    #expect(client.contains("decoder.container(keyedBy: SwiftAtproto.AnyCodingKeys.self)"))
    #expect(client.contains("if !SwiftAtproto.LexiconDecodingMode.shouldValidateConstraints(in: decoder)"))
    #expect(client.contains("throws(SwiftAtproto.LexiconConstraintError) {"))
    #expect(client.contains("throw SwiftAtproto.LexiconConstraintError.stringTooLong("))
    #expect(client.contains("case _other(SwiftAtproto.UnknownRecord)"))
    #expect(client.contains("public init(error: SwiftAtproto.UnExpectedError)"))
    #expect(client.contains("public var asParameters: SwiftAtproto.Parameters?"))
  }

  @Test("UnknownATPValue refers to records through the runtime protocol")
  func unknownValue() async throws {
    let unknown = try await generate().unknown
    #expect(unknown.contains("case record(any SwiftAtproto.ATProtoRecord)"))
    #expect(unknown.contains("[String: any SwiftAtproto.ATProtoRecord.Type]"))
  }

  @Test("the subscription source text is qualified")
  func subscriptionText() async throws {
    let client = try await generate().client
    #expect(client.contains("public enum Subscribe: SwiftAtproto.XRPCSubscription {"))
    #expect(client.contains("public struct Query: SwiftAtproto.XRPCInputQuery {"))
    #expect(client.contains("SwiftAtproto.Parameters(dictionary: ["))
  }
}
