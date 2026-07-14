import Foundation
import SwiftParser
import Testing

@testable import SwiftAtprotoLex

@Suite("Numeric-leading identifier escaping")
struct NumericIdentifierEscapeTests {
  // Direct unit test for the escape helper — digits must gain a leading `_`
  // so they form valid Swift identifiers, and reserved-word backticks are
  // preserved.
  @Test("escapedSwiftKeyword prepends _ for digit-leading identifiers")
  func numericLeadingIdentifiers() {
    #expect("0040000".escapedSwiftKeyword == "_0040000")
    #expect("0100644".escapedSwiftKeyword == "_0100644")
    #expect("default".escapedSwiftKeyword == "`default`")
    #expect("ordinary".escapedSwiftKeyword == "ordinary")
  }

  // End-to-end: a knownValues list whose entries start with digits must emit
  // escaped case names while keeping the original numeric string in `rawValue`.
  @Test("knownValues starting with digits emit _-prefixed case names")
  func numericKnownValuesGetPrefix() async throws {
    let root = FileManager.default.temporaryDirectory
      .appending(path: "swift-atproto-numeric-identifier-escape-\(UUID().uuidString)", directoryHint: .isDirectory)
    defer { try? FileManager.default.removeItem(at: root) }

    let input = root.appending(path: "input", directoryHint: .isDirectory)
    let output = root.appending(path: "output", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: input, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

    let fixture = """
      {
        "lexicon": 1,
        "id": "com.example.mode",
        "defs": {
          "main": {
            "type": "object",
            "required": ["mode"],
            "properties": {
              "mode": {"type": "string", "knownValues": ["0040000", "0100644"]}
            }
          }
        }
      }
      """
    try fixture.write(to: input.appending(path: "mode.json"), atomically: true, encoding: .utf8)

    try await SwiftAtprotoLex.main(outdir: output, path: input.path, generate: .client, pluginSource: .command)

    let source = try String(contentsOf: output.appending(path: "XRPCAPIClient.swift"), encoding: .utf8)
    let syntax = Parser.parse(source: source)

    #expect(!syntax.hasError)
    #expect(source.contains("case _0040000"))
    #expect(source.contains("case _0100644"))
  }
}
