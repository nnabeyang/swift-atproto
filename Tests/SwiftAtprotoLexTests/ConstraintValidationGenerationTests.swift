import Foundation
import SwiftParser
import SwiftSyntax
import Testing

@testable import SwiftAtprotoLex

@Suite("Constraint constants and validateConstraints() generation")
struct ConstraintValidationGenerationTests {
  private static let postFixture = """
    {
      "lexicon": 1,
      "id": "com.example.post",
      "defs": {
        "main": {
          "type": "record",
          "key": "tid",
          "record": {
            "type": "object",
            "required": ["text", "reply"],
            "properties": {
              "text": {"type": "string", "maxLength": 3000, "maxGraphemes": 300},
              "langs": {"type": "array", "maxLength": 3, "items": {"type": "string", "format": "language"}},
              "facets": {"type": "array", "items": {"type": "ref", "ref": "#facet"}},
              "embed": {"type": "union", "refs": ["com.example.video", "#mention"]},
              "reply": {"type": "ref", "ref": "#mention"},
              "attachment": {"type": "unknown"},
              "default": {"type": "integer", "minimum": 1, "maximum": 5}
            }
          }
        },
        "facet": {
          "type": "object",
          "required": ["features"],
          "properties": {
            "features": {"type": "array", "items": {"type": "union", "refs": ["#tag", "#mention"]}}
          }
        },
        "tag": {
          "type": "object",
          "required": ["tag"],
          "properties": {"tag": {"type": "string", "maxLength": 640, "maxGraphemes": 64}}
        },
        "mention": {
          "type": "object",
          "required": ["did"],
          "properties": {"did": {"type": "string", "format": "did"}}
        }
      }
    }
    """

  private static let videoFixture = """
    {
      "lexicon": 1,
      "id": "com.example.video",
      "defs": {
        "main": {
          "type": "object",
          "required": ["video"],
          "properties": {
            "video": {"type": "blob", "accept": ["video/mp4"], "maxSize": 300000000},
            "alt": {"type": "string", "maxGraphemes": 1000, "knownValues": ["none"]}
          }
        }
      }
    }
    """

  private struct Generated {
    let client: String
    let unknown: String
  }

  private func generate() async throws -> Generated {
    let root = FileManager.default.temporaryDirectory
      .appending(path: "swift-atproto-constraint-validation-\(UUID().uuidString)", directoryHint: .isDirectory)
    defer { try? FileManager.default.removeItem(at: root) }

    let input = root.appending(path: "input", directoryHint: .isDirectory)
    let output = root.appending(path: "output", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: input, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
    try Self.postFixture.write(to: input.appending(path: "post.json"), atomically: true, encoding: .utf8)
    try Self.videoFixture.write(to: input.appending(path: "video.json"), atomically: true, encoding: .utf8)

    try await SwiftAtprotoLex.main(outdir: output, path: input.path, generate: .client, pluginSource: .command)

    return Generated(
      client: try String(contentsOf: output.appending(path: "XRPCAPIClient.swift"), encoding: .utf8),
      unknown: try String(contentsOf: output.appending(path: "UnknownATPValue.swift"), encoding: .utf8)
    )
  }

  /// The source of the struct or enum named `name`, without the types nested
  /// in it, so that an expectation about one type can't match another.
  private func declaration(_ name: String, in source: String) throws -> String {
    final class Finder: SyntaxVisitor {
      let name: String
      var found: String?
      init(name: String) {
        self.name = name
        super.init(viewMode: .sourceAccurate)
      }
      override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        if node.name.text == name { found = Self.members(of: node.memberBlock) }
        return .visitChildren
      }
      override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
        if node.name.text == name { found = Self.members(of: node.memberBlock) }
        return .visitChildren
      }
      static func members(of block: MemberBlockSyntax) -> String {
        block.members
          .filter { !$0.decl.is(StructDeclSyntax.self) && !$0.decl.is(EnumDeclSyntax.self) }
          .map(\.description)
          .joined()
      }
    }
    let finder = Finder(name: name)
    finder.walk(Parser.parse(source: source))
    return try #require(finder.found, "no declaration named \(name)")
  }

  /// The source of the `Constraints` enum nested in the type named `name`.
  private func constraints(of name: String, in source: String) throws -> String {
    final class Finder: SyntaxVisitor {
      let name: String
      var found: String?
      init(name: String) {
        self.name = name
        super.init(viewMode: .sourceAccurate)
      }
      override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        guard node.name.text == name else { return .visitChildren }
        found =
          node.memberBlock.members
          .compactMap { $0.decl.as(EnumDeclSyntax.self) }
          .first { $0.name.text == "Constraints" }?
          .description
        return .skipChildren
      }
    }
    let finder = Finder(name: name)
    finder.walk(Parser.parse(source: source))
    return try #require(finder.found, "no Constraints in \(name)")
  }

  /// The lines of `source` with their indentation removed.
  private func lines(_ source: String) -> [String] {
    source.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
  }

  @Test("the generated sources parse")
  func generatedSourcesParse() async throws {
    let generated = try await generate()
    #expect(!Parser.parse(source: generated.client).hasError)
    #expect(!Parser.parse(source: generated.unknown).hasError)
  }

  @Test("constrained fields get constants named after the field and the constraint")
  func constants() async throws {
    let generated = try await generate()

    let post = lines(try constraints(of: "Post", in: generated.client))
    #expect(post.contains("public static let textMaxLength: Swift.Int = 3000"))
    #expect(post.contains("public static let textMaxGraphemes: Swift.Int = 300"))
    #expect(post.contains("public static let langsMaxLength: Swift.Int = 3"))
    #expect(post.contains("public static let defaultMinimum: Swift.Int = 1"))
    #expect(post.contains("public static let defaultMaximum: Swift.Int = 5"))

    let video = lines(try constraints(of: "Video", in: generated.client))
    #expect(video.contains("public static let videoMaxSize: Swift.Int = 300000000"))
    #expect(video.contains("public static let altMaxGraphemes: Swift.Int = 1000"))

    let tag = lines(try constraints(of: "Post_Tag", in: generated.client))
    #expect(tag.contains("public static let tagMaxLength: Swift.Int = 640"))
    #expect(tag.contains("public static let tagMaxGraphemes: Swift.Int = 64"))
  }

  @Test("unconstrained types get no constants")
  func noConstantsWithoutConstraints() async throws {
    let generated = try await generate()
    #expect(!lines(try declaration("Post_Mention", in: generated.client)).contains("public enum Constraints {"))
    #expect(!lines(try declaration("Post_Facet", in: generated.client)).contains("public enum Constraints {"))
  }

  @Test("make reads the limits from the constants")
  func makeReadsConstants() async throws {
    let generated = try await generate()
    let post = lines(try declaration("Post", in: generated.client))
    #expect(post.contains("guard text.count <= Constraints.textMaxGraphemes else {"))
    #expect(post.contains(#"throw LexiconConstraintError.tooManyGraphemes("text", limit: Constraints.textMaxGraphemes)"#))
    #expect(post.contains("guard `default` >= Constraints.defaultMinimum else {"))
    #expect(!post.contains { $0.contains("<= 300 else") })

    let video = lines(try declaration("Video", in: generated.client))
    #expect(video.contains("guard Swift.Int(video.size) <= Constraints.videoMaxSize else {"))
    #expect(video.contains("guard alt.rawValue.count <= Constraints.altMaxGraphemes else {"))
  }

  @Test("validateConstraints() checks the nested values before the type's own fields")
  func validateVisitsNestedValues() async throws {
    let generated = try await generate()
    let post = lines(try declaration("Post", in: generated.client))

    #expect(post.contains("public func validateConstraints() throws(LexiconConstraintError) {"))
    let nested = [
      "try attachment?.validateConstraints()",
      "try embed?.validateConstraints()",
      "for element in facets ?? [] {",
      "try element.validateConstraints()",
      "try reply.validateConstraints()",
    ]
    for line in nested {
      #expect(post.contains(line), "missing \(line)")
    }
    // The own fields come after the nested values, as in strict decoding.
    let validateStart = try #require(post.firstIndex(of: "public func validateConstraints() throws(LexiconConstraintError) {"))
    let validateBody = post[validateStart...]
    let lastNested = try #require(validateBody.firstIndex(of: "try reply.validateConstraints()"))
    let firstOwn = try #require(validateBody.firstIndex(of: "guard text.utf8.count <= Constraints.textMaxLength else {"))
    #expect(lastNested < firstOwn)

    // Arrays of strings have no nested values to check.
    #expect(!post.contains("for element in langs ?? [] {"))

    let facet = lines(try declaration("Post_Facet", in: generated.client))
    #expect(facet.contains("for element in features {"))
  }

  @Test("types with nothing to check rely on the protocol's default validateConstraints()")
  func noValidateWithoutChecks() async throws {
    let generated = try await generate()
    let mention = lines(try declaration("Post_Mention", in: generated.client))
    #expect(!mention.contains { $0.contains("func validateConstraints()") })
    #expect(generated.client.contains("public struct Post_Mention: Codable, Hashable, Sendable, LexiconValidatable {"))
  }

  @Test("unions validate the value of each case and skip unknown types")
  func unionValidatesCases() async throws {
    let generated = try await generate()
    #expect(generated.client.contains("public indirect enum Post_Embed: Codable, Hashable, Sendable, LexiconValidatable {"))

    let embed = lines(try declaration("Post_Embed", in: generated.client))
    #expect(embed.contains("public func validateConstraints() throws(LexiconConstraintError) {"))
    #expect(embed.contains("case .video(let value):"))
    #expect(embed.contains("case .postMention(let value):"))
    #expect(embed.contains("try value.validateConstraints()"))
    #expect(embed.contains("case ._other:"))
    #expect(embed.contains("break"))
  }

  @Test("UnknownATPValue validates the record it holds")
  func unknownValueValidatesRecord() async throws {
    let generated = try await generate()
    #expect(generated.unknown.contains("public nonisolated enum UnknownATPValue: UnknownATPValueProtocol, LexiconValidatable {"))

    let unknown = lines(try declaration("UnknownATPValue", in: generated.unknown))
    #expect(unknown.contains("public func validateConstraints() throws(LexiconConstraintError) {"))
    #expect(unknown.contains("case .record(let record):"))
    #expect(unknown.contains("try record.validateConstraints()"))
    #expect(unknown.contains("case .any:"))
  }
}
