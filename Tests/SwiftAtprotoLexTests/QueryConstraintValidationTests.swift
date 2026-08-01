import Foundation
import SwiftParser
import Testing

@testable import SwiftAtprotoLex

@Suite("Query constraint validation generation")
struct QueryConstraintValidationTests {
  private func generateClient(fixtures: [String: String]) async throws -> String {
    let root = FileManager.default.temporaryDirectory
      .appending(path: "swift-atproto-query-constraints-\(UUID().uuidString)", directoryHint: .isDirectory)
    defer { try? FileManager.default.removeItem(at: root) }

    let input = root.appending(path: "input", directoryHint: .isDirectory)
    let output = root.appending(path: "output", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: input, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

    for (name, contents) in fixtures {
      try contents.write(to: input.appending(path: name), atomically: true, encoding: .utf8)
    }

    try await SwiftAtprotoLex.main(outdir: output, path: input.path, generate: .client, pluginSource: .command)
    return try String(contentsOf: output.appending(path: "XRPCAPIClient.swift"), encoding: .utf8)
  }

  private var constrainedFixture: String {
    """
    {
      "lexicon": 1,
      "id": "com.example.constrainedQuery",
      "defs": {
        "main": {
          "type": "query",
          "parameters": {
            "type": "params",
            "required": ["actor"],
            "properties": {
              "actor": {"type": "string"},
              "limit": {"type": "integer", "minimum": 1, "maximum": 100}
            }
          },
          "output": {
            "encoding": "application/json",
            "schema": {"type": "object", "properties": {"cursor": {"type": "string"}}}
          }
        }
      }
    }
    """
  }

  private var plainFixture: String {
    """
    {
      "lexicon": 1,
      "id": "com.example.plainQuery",
      "defs": {
        "main": {
          "type": "query",
          "parameters": {
            "type": "params",
            "properties": {
              "cursor": {"type": "string"}
            }
          },
          "output": {
            "encoding": "application/json",
            "schema": {"type": "object", "properties": {"cursor": {"type": "string"}}}
          }
        }
      }
    }
    """
  }

  @Test("constrained query clients construct input through the validating factory")
  func constrainedQueryClientsValidateInput() async throws {
    let source = try await generateClient(fixtures: [
      "constrained.json": constrainedFixture,
      "plain.json": plainFixture,
    ])
    let syntax = Parser.parse(source: source)

    #expect(!syntax.hasError)
    #expect(
      source.contains(
        "input: try Com.Example.ConstrainedQuery.Input.Query.make(actor: actor, limit: limit)"
      ))
    #expect(source.contains("throw LexiconConstraintError.integerBelowMinimum(\"limit\", minimum: 1)"))
    #expect(source.contains("throw LexiconConstraintError.integerAboveMaximum(\"limit\", maximum: 100)"))
  }

  @Test("unconstrained query clients keep the plain initializer")
  func unconstrainedQueryClientsKeepInit() async throws {
    let source = try await generateClient(fixtures: ["plain.json": plainFixture])
    let syntax = Parser.parse(source: source)

    #expect(!syntax.hasError)
    #expect(source.contains("input: .init(cursor: cursor)"))
    #expect(!source.contains("Input.Query.make("))
  }
}
