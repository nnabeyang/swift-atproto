import Foundation
import Testing

@testable import SwiftAtprotoLex

// A field that shares its name with a declaration the generator adds to its
// type stops generation with an error naming the field, and only when the
// generator would add that declaration.
@Suite("Generated name collisions")
struct GeneratedNameCollisionTests {
  private struct Output {
    let error: (any Error)?
    let writtenFiles: [String]
  }

  private func generate(_ fixtures: [String: String]) async throws -> Output {
    let root = FileManager.default.temporaryDirectory
      .appending(path: "swift-atproto-name-collision-\(UUID().uuidString)", directoryHint: .isDirectory)
    defer { try? FileManager.default.removeItem(at: root) }

    let input = root.appending(path: "input", directoryHint: .isDirectory)
    let output = root.appending(path: "output", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: input, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
    for (name, contents) in fixtures {
      try contents.write(to: input.appending(path: name), atomically: true, encoding: .utf8)
    }

    var error: (any Error)?
    do {
      try await SwiftAtprotoLex.main(outdir: output, path: input.path, generate: .client, pluginSource: .command)
    } catch let thrown {
      error = thrown
    }
    let written = try FileManager.default.contentsOfDirectory(atPath: output.path)
    return Output(error: error, writtenFiles: written)
  }

  private func object(_ id: String, properties: String) -> String {
    """
    {"lexicon": 1, "id": "\(id)", "defs": {"main": {"type": "object", "properties": {\(properties)}}}}
    """
  }

  // MARK: - Collisions

  @Test("a field named Constraints in a type with constraints")
  func constraintsField() async throws {
    let output = try await generate([
      "a.json": object("com.example.a", properties: #""Constraints": {"type": "string"}, "text": {"type": "string", "maxLength": 3}"#)
    ])
    #expect(
      output.error as? GeneratedNameCollisionError
        == .field(nsid: "com.example.a", typeName: "Com.Example.A", field: "Constraints", generatedName: "Constraints enum"))
    #expect(output.writtenFiles.isEmpty)
  }

  @Test("a field named validateConstraints in a record with constraints")
  func validateConstraintsFieldInRecord() async throws {
    let record = """
      {"lexicon": 1, "id": "com.example.r", "defs": {"main": {"type": "record", "key": "tid", "record": {"type": "object",
        "properties": {"validateConstraints": {"type": "boolean"}, "text": {"type": "string", "maxGraphemes": 3}}}}}}
      """
    let output = try await generate(["r.json": record])
    #expect(
      output.error as? GeneratedNameCollisionError
        == .field(
          nsid: "com.example.r", typeName: "Com.Example.R", field: "validateConstraints",
          generatedName: "validateConstraints() method"))
    #expect(output.writtenFiles.isEmpty)
  }

  @Test("a field named validateConstraints in a type that validates only nested values")
  func validateConstraintsFieldWithNestedValues() async throws {
    let output = try await generate([
      "inner.json": object("com.example.inner", properties: #""text": {"type": "string", "maxLength": 3}"#),
      "outer.json": object(
        "com.example.outer",
        properties: #""validateConstraints": {"type": "boolean"}, "inner": {"type": "ref", "ref": "com.example.inner"}"#),
    ])
    #expect(
      output.error as? GeneratedNameCollisionError
        == .field(
          nsid: "com.example.outer", typeName: "Com.Example.Outer", field: "validateConstraints",
          generatedName: "validateConstraints() method"))
    #expect(output.writtenFiles.isEmpty)
  }

  @Test("a query parameter named Constraints in a query with constrained parameters")
  func constraintsQueryParameter() async throws {
    let query = """
      {"lexicon": 1, "id": "com.example.search", "defs": {"main": {"type": "query",
        "parameters": {"type": "params", "properties": {"Constraints": {"type": "string"}, "q": {"type": "string", "maxLength": 20}}},
        "output": {"encoding": "application/json", "schema": {"type": "object", "properties": {}}}}}}
      """
    let output = try await generate(["search.json": query])
    #expect(
      output.error as? GeneratedNameCollisionError
        == .field(
          nsid: "com.example.search", typeName: "Com.Example.Search.Input.Query", field: "Constraints",
          generatedName: "Constraints enum"))
    #expect(output.writtenFiles.isEmpty)
  }

  // A generated type or namespace named like a module the generated code
  // qualifies with would be found first and hide the module.
  @Test(
    "a generated type or namespace named like a module the generated code refers to",
    arguments: [
      ("com.example.swiftAtproto", "Com.Example.SwiftAtproto"),
      ("com.example.foundation", "Com.Example.Foundation"),
      ("com.example.swift", "Com.Example.Swift"),
      ("com.swift.example", "Com.Swift"),
    ])
  func moduleNames(nsid: String, typeName: String) async throws {
    let output = try await generate(["x.json": object(nsid, properties: #""x": {"type": "string"}"#)])
    #expect(output.error as? GeneratedNameCollisionError == .moduleName(nsid: nsid, typeName: typeName))
    #expect(output.writtenFiles.isEmpty)
  }

  @Test("the module error names the module it hides")
  func moduleNameDescription() {
    #expect(
      GeneratedNameCollisionError.moduleName(nsid: "com.example.swiftAtproto", typeName: "Com.Example.SwiftAtproto").description
        == "com.example.swiftAtproto generates Com.Example.SwiftAtproto, which hides the SwiftAtproto module that the generated code refers to; rename it in the Lexicon"
    )
  }

  @Test("the error names the field, the type, and the NSID")
  func description() {
    let error = GeneratedNameCollisionError.field(
      nsid: "com.example.a", typeName: "Com.Example.A", field: "Constraints", generatedName: "Constraints enum")
    #expect(
      error.description
        == "field Constraints of Com.Example.A (com.example.a) collides with the generated Constraints enum; rename the field in the Lexicon"
    )
  }

  // MARK: - No collision

  @Test("the same names generate when the type doesn't get those declarations")
  func noCollisionWithoutTheDeclarations() async throws {
    let query = """
      {"lexicon": 1, "id": "com.example.plainQuery", "defs": {"main": {"type": "query",
        "parameters": {"type": "params", "properties": {"Constraints": {"type": "string"}}},
        "output": {"encoding": "application/json", "schema": {"type": "object", "properties": {}}}}}}
      """
    let output = try await generate([
      // No limit and no nested value: neither `Constraints` nor `validateConstraints()`.
      "plain.json": object(
        "com.example.plain", properties: #""Constraints": {"type": "string"}, "validateConstraints": {"type": "boolean"}"#),
      "plainQuery.json": query,
    ])
    #expect(output.error == nil)
    #expect(output.writtenFiles.contains("XRPCAPIClient.swift"))
  }
}
