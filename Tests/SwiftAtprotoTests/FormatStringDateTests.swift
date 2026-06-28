import Foundation
import Testing

@testable import SwiftAtproto

struct FormatStringDateTests {
  @Test func decodePreservesWireStringAndTypedYieldsDate() throws {
    let data = Data("\"2024-01-15T12:30:00+09:00\"".utf8)
    let value = try JSONDecoder().decode(FormatString<Date>.self, from: data)
    #expect(value.rawValue == "2024-01-15T12:30:00+09:00")
    #expect(value.typed == (try Date(string: "2024-01-15T12:30:00+09:00")))
  }

  @Test func invalidDatetimeDecodesLenientlyWithNilTyped() throws {
    let data = Data("\"not-a-datetime\"".utf8)
    let value = try JSONDecoder().decode(FormatString<Date>.self, from: data)
    #expect(value.rawValue == "not-a-datetime")
    #expect(value.typed == nil)
  }

  @Test func encodeEmitsWireString() throws {
    let value = FormatString<Date>(rawValue: "2024-01-15T12:30:00+09:00")
    let data = try JSONEncoder().encode(value)
    #expect(String(decoding: data, as: UTF8.self) == "\"2024-01-15T12:30:00+09:00\"")
  }

  @Test func initFromDateUsesCanonicalRawValue() throws {
    let date = try Date(string: "2024-01-15T12:30:00Z")
    let value = FormatString(date)
    #expect(value.rawValue == "2024-01-15T12:30:00.000Z")
    #expect(value.typed == date)
  }

  @Test func decodesTypicalUTCMillisecondDatetime() throws {
    let wire = "2024-01-15T12:30:00.123Z"
    let value = try JSONDecoder().decode(FormatString<Date>.self, from: Data("\"\(wire)\"".utf8))
    #expect(value.rawValue == wire)

    let reference = ISO8601DateFormatter()
    reference.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    let expected = try #require(reference.date(from: wire))
    let actual = try #require(value.typed)
    #expect(abs(actual.timeIntervalSince1970 - expected.timeIntervalSince1970) <= 0.001)
  }

  @Test func decodesDatetimeFieldInRecord() throws {
    struct Record: Codable {
      var createdAt: FormatString<Date>
    }
    let json = Data(#"{"createdAt":"2024-01-15T12:30:00.123Z"}"#.utf8)
    let record = try JSONDecoder().decode(Record.self, from: json)
    #expect(record.createdAt.rawValue == "2024-01-15T12:30:00.123Z")
    #expect(record.createdAt.typed != nil)
  }

  @Test func typedIsNilButTypedLenientIsNonNilForTzOmittedInput() throws {
    let data = Data("\"1985-04-12T23:20:50.123\"".utf8)
    let value = try JSONDecoder().decode(FormatString<Date>.self, from: data)
    #expect(value.rawValue == "1985-04-12T23:20:50.123")
    #expect(value.typed == nil)
    #expect(value.typedLenient != nil)
  }

  @Test func descriptionIsRawValue() {
    let value = FormatString<Date>(rawValue: "2024-01-15T12:30:00+09:00")
    #expect(value.description == "2024-01-15T12:30:00+09:00")
    #expect("\(value)" == "2024-01-15T12:30:00+09:00")
  }

  // `Date.rawValue` is defined as `formatted(.atprotoDatetime)`; assert the public FormatStyle
  // accessor and the canonical formatting agree.
  @Test(arguments: [
    "2024-01-15T12:30:00.123Z",
    "1000-12-31T23:00:00.000Z",
    "0000-01-01T00:00:00.000Z",
    "9999-12-31T23:59:59.999Z",
  ])
  func formatStyleMatchesRawValue(_ wire: String) throws {
    let date = try Date(string: wire)
    #expect(date.formatted(.atprotoDatetime) == date.rawValue)
  }
}
