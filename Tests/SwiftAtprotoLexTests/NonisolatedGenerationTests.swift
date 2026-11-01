import Foundation
import SwiftParser
import SwiftSyntax
import Testing

@testable import SwiftAtprotoLex

#if os(macOS) || os(Linux)
  // `AccessModifier` comes from SourceControl on these platforms and from
  // SwiftAtprotoLex elsewhere.
  import SourceControl
#endif

@Suite("Generated top-level declarations are nonisolated")
struct NonisolatedGenerationTests {
  private static let fixtures: [String: String] = [
    // A record whose id doubles as a namespace prefix, so that the client
    // also emits a top-level extension on the record.
    "repo.json": """
    {
      "lexicon": 1,
      "id": "com.example.repo",
      "defs": {
        "main": {
          "type": "record",
          "key": "tid",
          "record": {
            "type": "object",
            "required": ["name"],
            "properties": {"name": {"type": "string"}}
          }
        }
      }
    }
    """,
    "issueComment.json": """
    {
      "lexicon": 1,
      "id": "com.example.repo.issue.comment",
      "defs": {
        "main": {
          "type": "object",
          "required": ["note"],
          "properties": {"note": {"type": "string"}}
        }
      }
    }
    """,
    "getThing.json": """
    {
      "lexicon": 1,
      "id": "com.example.thing.getThing",
      "defs": {
        "main": {
          "type": "query",
          "parameters": {
            "type": "params",
            "required": ["name"],
            "properties": {"name": {"type": "string"}}
          },
          "output": {
            "encoding": "application/json",
            "schema": {
              "type": "object",
              "required": ["name"],
              "properties": {"name": {"type": "string"}}
            }
          }
        }
      }
    }
    """,
    "putThing.json": """
    {
      "lexicon": 1,
      "id": "com.example.thing.putThing",
      "defs": {
        "main": {
          "type": "procedure",
          "input": {
            "encoding": "application/json",
            "schema": {
              "type": "object",
              "required": ["name"],
              "properties": {"name": {"type": "string"}}
            }
          }
        }
      }
    }
    """,
  ]

  private static let generatedFiles = [
    "XRPCAPIClient.swift",
    "UnknownATPValue.swift",
    "XRPCAPIProtocol.swift",
  ]

  @Test(
    "every top-level declaration carries nonisolated",
    arguments: [AccessModifier.public, .internal, .package])
  func topLevelDeclarationsAreNonisolated(accessModifier: AccessModifier) async throws {
    let root = FileManager.default.temporaryDirectory
      .appending(path: "swift-atproto-nonisolated-\(UUID().uuidString)", directoryHint: .isDirectory)
    defer { try? FileManager.default.removeItem(at: root) }

    let input = root.appending(path: "input", directoryHint: .isDirectory)
    let output = root.appending(path: "output", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: input, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
    for (name, body) in Self.fixtures {
      try body.write(to: input.appending(path: name), atomically: true, encoding: .utf8)
    }

    try await SwiftAtprotoLex.main(
      outdir: output,
      path: input.path,
      generate: [.client, .server],
      accessModifier: accessModifier,
      pluginSource: .command)

    for file in Self.generatedFiles {
      let source = try String(contentsOf: output.appending(path: file), encoding: .utf8)
      let syntax = Parser.parse(source: source)
      #expect(!syntax.hasError, "\(file)")

      let declarations = syntax.statements.compactMap { item -> DeclSyntax? in
        guard case .decl(let decl) = item.item, !decl.is(ImportDeclSyntax.self) else { return nil }
        return decl
      }
      #expect(!declarations.isEmpty, "\(file)")
      for decl in declarations {
        let modifiers = decl.asProtocol(WithModifiersSyntax.self)?.modifiers ?? []
        #expect(
          modifiers.contains { $0.name.tokenKind == .keyword(.nonisolated) },
          "\(file): \(decl.trimmedDescription.prefix(80))")
      }
    }

    let client = try String(contentsOf: output.appending(path: "XRPCAPIClient.swift"), encoding: .utf8)
    // The modifier must not separate an extension from its keyword.
    #expect(client.contains("\nnonisolated extension Com.Example.Repo "))
    #expect(client.contains("\nnonisolated extension XRPCCallable "))
  }
}
