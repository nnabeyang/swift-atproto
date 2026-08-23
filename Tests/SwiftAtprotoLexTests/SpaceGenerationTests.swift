import Foundation
import SwiftParser
import Testing

@testable import SwiftAtprotoLex

@Suite("Space type declaration generation")
struct SpaceGenerationTests {
  @Test("space declarations generate LexSpace conformances")
  func spaceDeclarationsGenerateLexSpaceConformances() async throws {
    let source = try await generateClient(fixtures: [
      "forum.json": Self.basicSpace,
      "empty.json": Self.spaceWithEmptyCollections,
    ])
    #expect(!Parser.parse(source: source).hasError)

    #expect(source.contains("public enum Forum: LexSpace"))
    #expect(source.contains(#"public static let id = "com.atmoboards.forum""#))
    #expect(source.contains("public static let key: LexRecordKeyType = .any"))
    #expect(source.contains(#"public static let name: Swift.String = "AtmoBoards Forum""#))
    #expect(source.contains(#"public static let description: Swift.String? = "A discussion forum""#))
    #expect(source.contains(#""es": "Foro AtmoBoards""#))
    #expect(source.contains(#""ja": "AtmoBoards 掲示板""#))
    #expect(source.contains(#"FormatString<NSID>(rawValue: "com.atmoboards.thread")"#))
    #expect(source.contains(#"FormatString<NSID>(rawValue: "com.atmoboards.reply")"#))

    #expect(source.contains("public enum Empty: LexSpace"))
    #expect(source.contains("public static let key: LexRecordKeyType = .tid"))
    #expect(source.contains("public static let nameLang: [Swift.String: Swift.String]? = nil"))
    #expect(source.contains("public static let collections: [FormatString<NSID>] = []"))
    #expect(source.contains("public static let description: Swift.String? = nil"))
  }

  // The reference implementation rejects six space fixtures. swift-atproto
  // rejects the three that omit a required field, which is the same strictness
  // the other primary definitions already apply.
  @Test(arguments: [Self.spaceMissingName, Self.spaceMissingKey, Self.spaceMissingCollections])
  func spaceMissingARequiredFieldFailsToDecode(_ fixture: String) {
    #expect(throws: (any Error).self) {
      try JSONDecoder().decode(Schema.self, from: Data(fixture.utf8))
    }
  }

  // The remaining three are accepted here on purpose, and this test pins that
  // down so a change in behaviour is deliberate rather than incidental.
  //
  // - The key vocabulary is open, so an unrecognized key type is carried as a
  //   raw value the way an unknown permission resource already is.
  // - A collection is generated as `FormatString<NSID>`, which keeps the wire
  //   string verbatim and reports the malformed value through `typed`.
  // - Rejecting a primary definition placed outside `main` would be a
  //   schema-wide rule; `record`, `query`, and the rest do not enforce it
  //   either.
  @Test(arguments: [Self.spaceWithInvalidKeyType, Self.spaceWithNonNSIDCollection, Self.spaceAsNonMainDefinition])
  func spaceFixturesOutsideRequiredFieldCheckingDecode(_ fixture: String) throws {
    let schema = try JSONDecoder().decode(Schema.self, from: Data(fixture.utf8))
    let definition = try #require(schema.defs.first?.value)
    #expect(definition.type.description == "space")
  }

  @Test("an unrecognized key type is generated as a raw value")
  func unrecognizedKeyTypeIsGeneratedAsARawValue() async throws {
    let source = try await generateClient(fixtures: ["space.json": Self.spaceWithInvalidKeyType])
    #expect(!Parser.parse(source: source).hasError)
    #expect(source.contains(#"public static let key: LexRecordKeyType = LexRecordKeyType(rawValue: "bogus")"#))
  }

  @Test("a literal key type keeps its payload")
  func literalKeyTypeKeepsItsPayload() async throws {
    let source = try await generateClient(fixtures: ["space.json": Self.spaceWithLiteralKey])
    #expect(!Parser.parse(source: source).hasError)
    #expect(source.contains(#"public static let key: LexRecordKeyType = LexRecordKeyType(rawValue: "literal:self")"#))
  }

  private func generateClient(fixtures: [String: String]) async throws -> String {
    let root = FileManager.default.temporaryDirectory
      .appending(path: "swift-atproto-space-generation-\(UUID().uuidString)", directoryHint: .isDirectory)
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

  // Fixtures come verbatim from the reference implementation's lexicon tests at
  // the pinned alpha commit (packages/lex/lex-document/tests/lexicon-valid.json).
  static let basicSpace = """
    {
      "lexicon": 1,
      "id": "com.atmoboards.forum",
      "defs": {
        "main": {
          "type": "space",
          "key": "any",
          "name": "AtmoBoards Forum",
          "description": "A discussion forum",
          "name:lang": {
            "es": "Foro AtmoBoards",
            "ja": "AtmoBoards 掲示板"
          },
          "collections": [
            "com.atmoboards.thread",
            "com.atmoboards.reply"
          ]
        }
      }
    }
    """

  static let spaceWithEmptyCollections = """
    {
      "lexicon": 1,
      "id": "com.example.empty",
      "defs": {
        "main": {
          "type": "space",
          "key": "tid",
          "name": "Empty Space",
          "collections": []
        }
      }
    }
    """

  // Fixtures the reference implementation lists as invalid
  // (packages/lex/lex-document/tests/lexicon-invalid.json).
  static let spaceMissingName = """
    {
      "lexicon": 1,
      "id": "com.example.space",
      "defs": {
        "main": {
          "type": "space",
          "collections": []
        }
      }
    }
    """

  static let spaceMissingKey = """
    {
      "lexicon": 1,
      "id": "com.example.space",
      "defs": {
        "main": {
          "type": "space",
          "name": "Example Space",
          "collections": []
        }
      }
    }
    """

  static let spaceMissingCollections = """
    {
      "lexicon": 1,
      "id": "com.example.space",
      "defs": {
        "main": {
          "type": "space",
          "name": "Example Space"
        }
      }
    }
    """

  static let spaceWithInvalidKeyType = """
    {
      "lexicon": 1,
      "id": "com.example.space",
      "defs": {
        "main": {
          "type": "space",
          "key": "bogus",
          "name": "Example Space",
          "collections": []
        }
      }
    }
    """

  static let spaceWithNonNSIDCollection = """
    {
      "lexicon": 1,
      "id": "com.example.space",
      "defs": {
        "main": {
          "type": "space",
          "key": "any",
          "name": "Example Space",
          "collections": [
            "not-a-valid-nsid"
          ]
        }
      }
    }
    """

  static let spaceAsNonMainDefinition = """
    {
      "lexicon": 1,
      "id": "com.example.space",
      "defs": {
        "demo": {
          "type": "space",
          "key": "any",
          "name": "Example Space",
          "collections": []
        }
      }
    }
    """

  // Not a reference fixture: `literal:` is the one key type that carries a
  // payload, and no valid-side fixture exercises it.
  static let spaceWithLiteralKey = """
    {
      "lexicon": 1,
      "id": "com.example.space",
      "defs": {
        "main": {
          "type": "space",
          "key": "literal:self",
          "name": "Example Space",
          "collections": []
        }
      }
    }
    """
}
