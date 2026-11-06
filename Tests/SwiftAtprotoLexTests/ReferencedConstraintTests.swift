import Foundation
import SwiftParser
import Testing

@testable import SwiftAtprotoLex

// A field that refers to a string definition takes that definition's limits
// as its own: they get constants and are checked wherever the field's limits
// are, measured as the type the reference is generated with.
@Suite("Constraints of referenced string definitions")
struct ReferencedConstraintTests {
  private static let fixtures: [String: String] = [
    "post.json": """
    {"lexicon": 1, "id": "com.example.post", "defs": {
      "main": {"type": "object", "properties": {
        "target": {"type": "ref", "ref": "#target"},
        "targets": {"type": "array", "items": {"type": "ref", "ref": "#target"}},
        "author": {"type": "ref", "ref": "com.example.defs#author"},
        "note": {"type": "ref", "ref": "com.example.defs#note"},
        "embed": {"type": "ref", "ref": "com.example.defs#embed"}
      }},
      "onlyReferenced": {"type": "object", "properties": {
        "note": {"type": "ref", "ref": "com.example.defs#note"}
      }},
      "target": {"type": "string", "knownValues": ["content", "tag"], "maxLength": 20, "maxGraphemes": 5}
    }}
    """,
    "defs.json": """
    {"lexicon": 1, "id": "com.example.defs", "defs": {
      "author": {"type": "string", "format": "did", "maxLength": 30},
      "note": {"type": "string", "maxGraphemes": 4},
      "embed": {"type": "object", "properties": {"x": {"type": "string"}}}
    }}
    """,
  ]

  private func generate() async throws -> String {
    let root = FileManager.default.temporaryDirectory
      .appending(path: "swift-atproto-referenced-constraints-\(UUID().uuidString)", directoryHint: .isDirectory)
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

  @Test("the limits of a referenced definition get constants")
  func constants() async throws {
    let client = lines(try await generate())
    #expect(client.contains("public static let targetMaxLength: Swift.Int = 20"))
    #expect(client.contains("public static let targetMaxGraphemes: Swift.Int = 5"))
    #expect(client.contains("public static let targetsItemMaxLength: Swift.Int = 20"))
    #expect(client.contains("public static let targetsItemMaxGraphemes: Swift.Int = 5"))
    // From another document.
    #expect(client.contains("public static let authorMaxLength: Swift.Int = 30"))
    #expect(client.contains("public static let noteMaxGraphemes: Swift.Int = 4"))
  }

  @Test("a referenced definition is measured as the type it is generated with")
  func measures() async throws {
    let client = lines(try await generate())
    // knownValues: the definition's own type, also as an element.
    #expect(client.contains("guard target.rawValue.utf8.count <= Constraints.targetMaxLength else {"))
    #expect(client.contains("guard element.rawValue.count <= Constraints.targetsItemMaxGraphemes else {"))
    #expect(client.contains("for (index, element) in targets.enumerated() {"))
    // format: FormatString.
    #expect(client.contains("guard author.rawValue.utf8.count <= Constraints.authorMaxLength else {"))
    // A plain string.
    #expect(client.contains("guard note.count <= Constraints.noteMaxGraphemes else {"))
  }

  @Test("a type whose only limits are referenced gets the checks")
  func onlyReferencedLimits() async throws {
    let client = try await generate()
    #expect(client.contains("public struct Post_OnlyReferenced: "))
    let start = try #require(client.range(of: "public struct Post_OnlyReferenced: "))
    let declaration = String(client[start.lowerBound...].prefix(4000))
    #expect(declaration.contains("public static let noteMaxGraphemes: Swift.Int = 4"))
    #expect(declaration.contains("public static func make("))
    #expect(declaration.contains("public func validateConstraints() throws(SwiftAtproto.LexiconConstraintError) {"))
  }

  @Test("a reference to an object brings no limits")
  func objectReference() async throws {
    let client = lines(try await generate())
    #expect(!client.contains { $0.contains("embedMax") || $0.contains("embedMin") })
    // It is checked through its own validateConstraints() instead.
    #expect(client.contains("try embed?.validateConstraints()"))
  }
}
