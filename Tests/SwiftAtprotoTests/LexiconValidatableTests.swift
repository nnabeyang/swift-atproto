import Foundation
import Testing

@testable import SwiftAtproto

// Mirrors the shape that code generation emits for a record holding a nested
// object, so that the runtime side of `validateConstraints()` (the protocol,
// its default implementation, and dispatch through `any ATProtoRecord`) is
// exercised without generating code.

private struct MirrorTag: Codable, Hashable, Sendable, LexiconValidatable {
  enum Constraints {
    static let tagMaxGraphemes: Int = 4
  }

  let tag: String

  func validateConstraints() throws(LexiconConstraintError) {
    guard tag.count <= Constraints.tagMaxGraphemes else {
      throw LexiconConstraintError.tooManyGraphemes("tag", limit: Constraints.tagMaxGraphemes)
    }
  }
}

// Declares no constraint and holds nothing to check, so it is generated
// without a `validateConstraints()` of its own.
private struct MirrorMention: Codable, Hashable, Sendable, LexiconValidatable {
  let did: String
}

private struct MirrorPost: ATProtoRecord {
  static let nsId = "com.example.post"

  enum Constraints {
    static let textMaxGraphemes: Int = 10
  }

  let text: String
  let tags: [MirrorTag]?
  let mention: MirrorMention?

  func validateConstraints() throws(LexiconConstraintError) {
    for element in tags ?? [] {
      try element.validateConstraints()
    }
    try mention?.validateConstraints()
    guard text.count <= Constraints.textMaxGraphemes else {
      throw LexiconConstraintError.tooManyGraphemes("text", limit: Constraints.textMaxGraphemes)
    }
  }
}

// A record written by hand, which keeps compiling after `ATProtoRecord`
// began to refine `LexiconValidatable`.
private struct HandWrittenRecord: ATProtoRecord {
  static let nsId = "com.example.handWritten"
  let value: String
}

@Suite("LexiconValidatable")
struct LexiconValidatableTests {
  @Test("a value within its limits passes")
  func validValuePasses() throws {
    let post = MirrorPost(text: "hello", tags: [MirrorTag(tag: "abc")], mention: MirrorMention(did: "did:plc:abc"))
    try post.validateConstraints()
  }

  @Test("a violation in the value's own field is reported")
  func ownFieldViolation() {
    let post = MirrorPost(text: "12345678901", tags: nil, mention: nil)
    #expect(throws: LexiconConstraintError.self) { try post.validateConstraints() }
    #expect(describe { try post.validateConstraints() } == #"tooManyGraphemes("text", limit: 10)"#)
  }

  @Test("a violation in a nested value is reported")
  func nestedViolation() {
    let post = MirrorPost(text: "hello", tags: [MirrorTag(tag: "abc"), MirrorTag(tag: "abcde")], mention: nil)
    #expect(describe { try post.validateConstraints() } == #"tooManyGraphemes("tag", limit: 4)"#)
  }

  @Test("a type without its own validateConstraints() uses the default, which passes")
  func defaultImplementationPasses() throws {
    try MirrorMention(did: "did:plc:abc").validateConstraints()
    try HandWrittenRecord(value: String(repeating: "a", count: 10_000)).validateConstraints()
  }

  @Test("a record held as any ATProtoRecord dispatches to its own validateConstraints()")
  func existentialDispatch() {
    let record: any ATProtoRecord = MirrorPost(text: "12345678901", tags: nil, mention: nil)
    #expect(describe { try record.validateConstraints() } == #"tooManyGraphemes("text", limit: 10)"#)
  }

  @Test("validateConstraints() throws LexiconConstraintError without a cast")
  func typedThrows() {
    let post = MirrorPost(text: "12345678901", tags: nil, mention: nil)
    do {
      try post.validateConstraints()
      Issue.record("expected a violation")
    } catch {
      // `error` is a LexiconConstraintError here because of the typed throws.
      guard case .tooManyGraphemes(let field, let limit) = error else {
        Issue.record("unexpected \(error)")
        return
      }
      #expect(field == "text")
      #expect(limit == MirrorPost.Constraints.textMaxGraphemes)
    }
  }

  /// The violation `body` reports, or `nil` when it reports none.
  private func describe(_ body: () throws -> Void) -> String? {
    do {
      try body()
      return nil
    } catch let error as LexiconConstraintError {
      return "\(error)"
    } catch {
      return "unexpected \(error)"
    }
  }
}
