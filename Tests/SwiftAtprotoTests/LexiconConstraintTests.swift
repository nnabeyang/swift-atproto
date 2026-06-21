import Foundation
import XCTest

@testable import SwiftAtproto

private struct ConstrainedRecord: Codable, Hashable, Sendable {
  let text: String
  let limit: Int?
  let _unknownValues: [String: AnyCodable]

  public init(text: String, limit: Int? = nil) {
    self.text = text
    self.limit = limit
    self._unknownValues = [:]
  }

  public static func make(text: String, limit: Int? = nil) throws -> Self {
    guard text.utf8.count <= 3000 else {
      throw LexiconConstraintError.stringTooLong("text", limit: 3000)
    }
    guard text.count <= 300 else {
      throw LexiconConstraintError.tooManyGraphemes("text", limit: 300)
    }
    if let limit {
      guard limit >= 1 else {
        throw LexiconConstraintError.integerBelowMinimum("limit", minimum: 1)
      }
      guard limit <= 100 else {
        throw LexiconConstraintError.integerAboveMaximum("limit", maximum: 100)
      }
    }
    return Self(text: text, limit: limit)
  }

  enum CodingKeys: String, CodingKey {
    case text
    case limit
  }

  init(from decoder: any Decoder) throws {
    let keyedContainer = try decoder.container(keyedBy: CodingKeys.self)
    let text = try keyedContainer.decode(String.self, forKey: .text)
    let limit = try keyedContainer.decodeIfPresent(Int.self, forKey: .limit)
    do {
      self = try Self.make(text: text, limit: limit)
    } catch let error as LexiconConstraintError {
      throw DecodingError.dataCorrupted(
        .init(codingPath: decoder.codingPath, debugDescription: "\(error)", underlyingError: error))
    }
  }
}

private enum KnownLang: RawRepresentable, Codable, Hashable, Sendable {
  case en
  case ja
  case _other(String)

  init(rawValue: String) {
    switch rawValue {
    case "en": self = .en
    case "ja": self = .ja
    default: self = ._other(rawValue)
    }
  }

  var rawValue: String {
    switch self {
    case .en: return "en"
    case .ja: return "ja"
    case ._other(let s): return s
    }
  }
}

private struct KnownValuesRecord: Sendable {
  let lang: KnownLang

  public init(lang: KnownLang) {
    self.lang = lang
  }

  public static func make(lang: KnownLang) throws -> Self {
    guard lang.rawValue.utf8.count <= 5 else {
      throw LexiconConstraintError.stringTooLong("lang", limit: 5)
    }
    return Self(lang: lang)
  }
}

final class LexiconConstraintTests: XCTestCase {
  func testValidValuesSucceed() throws {
    let record = try ConstrainedRecord.make(text: "hello", limit: 50)
    XCTAssertEqual(record.text, "hello")
    XCTAssertEqual(record.limit, 50)
  }

  func testIntegerOutOfRangeThrows() throws {
    XCTAssertThrowsError(try ConstrainedRecord.make(text: "ok", limit: 0)) { error in
      guard case LexiconConstraintError.integerBelowMinimum("limit", let minimum) = error else {
        return XCTFail("expected integerBelowMinimum, got \(error)")
      }
      XCTAssertEqual(minimum, 1)
    }
    XCTAssertThrowsError(try ConstrainedRecord.make(text: "ok", limit: 101)) { error in
      guard case LexiconConstraintError.integerAboveMaximum("limit", let maximum) = error else {
        return XCTFail("expected integerAboveMaximum, got \(error)")
      }
      XCTAssertEqual(maximum, 100)
    }
  }

  func testTooManyGraphemesThrows() throws {
    // stays under the UTF-8 byte limit while exceeding the grapheme limit
    let manyGraphemes = String(repeating: "a", count: 301)
    XCTAssertThrowsError(try ConstrainedRecord.make(text: manyGraphemes)) { error in
      guard case LexiconConstraintError.tooManyGraphemes(let field, let limit) = error else {
        return XCTFail("expected tooManyGraphemes, got \(error)")
      }
      XCTAssertEqual(field, "text")
      XCTAssertEqual(limit, 300)
    }
  }

  func testStringTooLongThrows() throws {
    let tooLong = String(repeating: "a", count: 3001)
    XCTAssertThrowsError(try ConstrainedRecord.make(text: tooLong)) { error in
      guard case LexiconConstraintError.stringTooLong(let field, let limit) = error else {
        return XCTFail("expected stringTooLong, got \(error)")
      }
      XCTAssertEqual(field, "text")
      XCTAssertEqual(limit, 3000)
    }
  }

  func testDecodeViolationConvertedToDecodingError() throws {
    let tooLong = String(repeating: "a", count: 3001)
    let json = try JSONEncoder().encode(["text": tooLong])
    XCTAssertThrowsError(try JSONDecoder().decode(ConstrainedRecord.self, from: json)) { error in
      guard case DecodingError.dataCorrupted(let context) = error else {
        return XCTFail("expected DecodingError.dataCorrupted, got \(error)")
      }
      guard let underlying = context.underlyingError, underlying is LexiconConstraintError else {
        return XCTFail("expected underlyingError to be LexiconConstraintError, got \(String(describing: context.underlyingError))")
      }
    }
  }

  func testDecodeValidSucceeds() throws {
    let json = try JSONEncoder().encode(["text": "hello world"])
    let record = try JSONDecoder().decode(ConstrainedRecord.self, from: json)
    XCTAssertEqual(record.text, "hello world")
  }

  func testKnownValuesOtherWithinLimitSucceeds() throws {
    let record = try KnownValuesRecord.make(lang: ._other("en-US"))
    XCTAssertEqual(record.lang.rawValue, "en-US")
  }

  func testKnownValuesOtherTooLongThrows() throws {
    XCTAssertThrowsError(try KnownValuesRecord.make(lang: ._other("en-USABC"))) { error in
      guard case LexiconConstraintError.stringTooLong(let field, let limit) = error else {
        return XCTFail("expected stringTooLong, got \(error)")
      }
      XCTAssertEqual(field, "lang")
      XCTAssertEqual(limit, 5)
    }
  }

  func testKnownValuesNamedCaseNotChecked() throws {
    let record = try KnownValuesRecord.make(lang: .en)
    XCTAssertEqual(record.lang.rawValue, "en")
  }
}
