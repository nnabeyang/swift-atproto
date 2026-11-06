import Foundation
import SwiftParser
import Testing

@testable import SwiftAtprotoLex

// The limits in an array's `items` apply to each element. They are checked
// wherever the field's own limits are, through the same `make` (strict
// decoding, validateConstraints(), Input.Query.make and the server), and the
// error names the element by its position: `tags[2]`.
@Suite("Array element constraints")
struct ArrayElementConstraintTests {
  private static let fixtures: [String: String] = [
    "post.json": """
    {"lexicon": 1, "id": "com.example.post", "defs": {
      "main": {"type": "record", "key": "tid", "record": {"type": "object", "required": ["scores"], "properties": {
        "tags": {"type": "array", "maxLength": 3, "items": {"type": "string", "maxLength": 20, "maxGraphemes": 5}},
        "scores": {"type": "array", "items": {"type": "integer", "minimum": 0, "maximum": 10}},
        "labels": {"type": "array", "items": {"type": "string", "maxLength": 4, "knownValues": ["spam"]}},
        "authors": {"type": "array", "items": {"type": "string", "format": "did", "maxLength": 20}},
        "images": {"type": "array", "items": {"type": "blob", "maxSize": 1000}}
      }}},
      "onlyElements": {"type": "object", "required": ["langs"], "properties": {
        "langs": {"type": "array", "items": {"type": "string", "maxGraphemes": 3}}
      }}
    }}
    """,
    "search.json": """
    {"lexicon": 1, "id": "com.example.search", "defs": {"main": {"type": "query",
      "parameters": {"type": "params", "properties": {"ids": {"type": "array", "items": {"type": "string", "maxLength": 5}}}},
      "output": {"encoding": "application/json", "schema": {"type": "object", "properties": {}}}}}}
    """,
  ]

  private func generate(withServer: Bool = false) async throws -> (client: String, server: String?) {
    let root = FileManager.default.temporaryDirectory
      .appending(path: "swift-atproto-element-constraints-\(UUID().uuidString)", directoryHint: .isDirectory)
    defer { try? FileManager.default.removeItem(at: root) }

    let input = root.appending(path: "input", directoryHint: .isDirectory)
    let output = root.appending(path: "output", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: input, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
    for (name, contents) in Self.fixtures {
      try contents.write(to: input.appending(path: name), atomically: true, encoding: .utf8)
    }

    if withServer {
      try await SwiftAtprotoLex.main(outdir: output, path: input.path, generate: [.client, .server], pluginSource: .command)
    } else {
      try await SwiftAtprotoLex.main(outdir: output, path: input.path, generate: .client, pluginSource: .command)
    }
    let client = try String(contentsOf: output.appending(path: "XRPCAPIClient.swift"), encoding: .utf8)
    let serverURL = output.appending(path: "XRPCAPIProtocol.swift")
    let server = FileManager.default.fileExists(atPath: serverURL.path) ? try String(contentsOf: serverURL, encoding: .utf8) : nil
    return (client, server)
  }

  /// The lines of `source` with their indentation removed.
  private func lines(_ source: String) -> [String] {
    source.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
  }

  @Test("the generated source parses")
  func parses() async throws {
    let generated = try await generate(withServer: true)
    #expect(!Parser.parse(source: generated.client).hasError)
    #expect(!Parser.parse(source: try #require(generated.server)).hasError)
  }

  @Test("element limits get constants named with Item")
  func constants() async throws {
    let client = lines(try await generate().client)
    #expect(client.contains("public static let tagsMaxLength: Swift.Int = 3"))
    #expect(client.contains("public static let tagsItemMaxLength: Swift.Int = 20"))
    #expect(client.contains("public static let tagsItemMaxGraphemes: Swift.Int = 5"))
    #expect(client.contains("public static let scoresItemMinimum: Swift.Int = 0"))
    #expect(client.contains("public static let scoresItemMaximum: Swift.Int = 10"))
    #expect(client.contains("public static let imagesItemMaxSize: Swift.Int = 1000"))
    #expect(client.contains("/// The `maxGraphemes` of each element of `tags` in the Lexicon."))
  }

  @Test("each element is checked in a loop that names its position")
  func loop() async throws {
    let client = lines(try await generate().client)
    #expect(client.contains("for (index, element) in tags.enumerated() {"))
    #expect(client.contains("guard element.count <= Constraints.tagsItemMaxGraphemes else {"))
    #expect(
      client.contains(
        #"throw SwiftAtproto.LexiconConstraintError.tooManyGraphemes("tags[\(index)]", limit: Constraints.tagsItemMaxGraphemes)"#))
    // The array's own limit is reported with the field's name, before the elements.
    #expect(client.contains(#"throw SwiftAtproto.LexiconConstraintError.arrayTooLong("tags", limit: Constraints.tagsMaxLength)"#))
    // A required array isn't optional-bound.
    #expect(client.contains("for (index, element) in scores.enumerated() {"))
    #expect(!client.contains("if let scores {"))
  }

  @Test("an element is measured as the type it has")
  func measures() async throws {
    let client = lines(try await generate().client)
    // An element with knownValues stays a String; a format wraps it.
    #expect(client.contains("guard element.utf8.count <= Constraints.labelsItemMaxLength else {"))
    #expect(client.contains("guard element.rawValue.utf8.count <= Constraints.authorsItemMaxLength else {"))
    #expect(client.contains("guard Swift.Int(element.size) <= Constraints.imagesItemMaxSize else {"))
    #expect(client.contains("guard element >= Constraints.scoresItemMinimum else {"))
  }

  @Test("a type whose only limits are on elements gets the checks")
  func onlyElementLimits() async throws {
    let client = try await generate().client
    #expect(client.contains("public static let langsItemMaxGraphemes: Swift.Int = 3"))
    #expect(client.contains("for (index, element) in langs.enumerated() {"))
    #expect(client.contains("if !SwiftAtproto.LexiconDecodingMode.shouldValidateConstraints(in: decoder)"))
  }

  @Test("query parameters check their elements on the client and the server")
  func queryParameters() async throws {
    let generated = try await generate(withServer: true)
    let client = lines(generated.client)
    #expect(client.contains("public static let idsItemMaxLength: Swift.Int = 5"))
    #expect(client.contains("for (index, element) in ids.enumerated() {"))
    #expect(generated.client.contains("Input.Query.make(ids: ids)"))
    // The server builds the parameters through the same `make`.
    #expect(try #require(generated.server).contains("Input.Query.make(ids:"))
  }
}
