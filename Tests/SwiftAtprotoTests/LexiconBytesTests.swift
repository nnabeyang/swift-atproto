import Foundation
import Testing

@testable import SwiftAtproto

private struct GeneratedBytesRecord: ATProtoRecord {
  static let nsId = "sh.tangled.repo.artifact"

  let type: String
  let tag: Data

  init(tag: Data) {
    type = Self.nsId
    self.tag = tag
  }

  enum CodingKeys: String, CodingKey {
    case type = "$type"
    case tag
  }
}

private struct ConstrainedBytesRecord: Codable, Hashable, Sendable {
  let tag: Data

  init(tag: Data) {
    self.tag = tag
  }

  enum CodingKeys: String, CodingKey {
    case tag
  }

  init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let tag = try container.decode(Data.self, forKey: .tag)
    guard tag.count >= 2 else {
      let error = LexiconConstraintError.bytesTooShort("tag", minimum: 2)
      throw DecodingError.dataCorrupted(
        .init(
          codingPath: decoder.codingPath,
          debugDescription: "\(error)",
          underlyingError: error
        )
      )
    }
    guard tag.count <= 4 else {
      let error = LexiconConstraintError.bytesTooLong("tag", limit: 4)
      throw DecodingError.dataCorrupted(
        .init(
          codingPath: decoder.codingPath,
          debugDescription: "\(error)",
          underlyingError: error
        )
      )
    }
    self.tag = tag
  }
}

private enum BytesProcedure: XRPCProcedure {
  static let id = "sh.tangled.repo.putArtifact"
  static let contentType = "application/json"
  typealias RequestBody = GeneratedBytesRecord
  typealias ResponseBody = GeneratedBytesRecord
  typealias Error = UnExpectedError
}

private enum RawBinaryProcedure: XRPCProcedure {
  static let id = "com.example.raw"
  static let contentType = "application/vnd.ipld.car"
  typealias RequestBody = Data
  typealias ResponseBody = Data
  typealias Error = UnExpectedError
}

private final class BytesRequestRecorder: @unchecked Sendable {
  var lastRequest: XRPCRequestComponents?
}

private struct BytesTestClient: @unchecked Sendable, _XRPCCallable {
  let responseData: Data
  let recorder: BytesRequestRecorder

  func getProxy(nsid _: String) -> String? { nil }

  func response(_ request: XRPCRequestComponents) async throws -> Data {
    recorder.lastRequest = request
    return responseData
  }
}

private func xrpcEncoder() -> JSONEncoder {
  let encoder = JSONEncoder()
  encoder.dataEncodingStrategy = .xrpc
  encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
  return encoder
}

private func xrpcDecoder() -> JSONDecoder {
  let decoder = JSONDecoder()
  decoder.dataDecodingStrategy = .xrpc
  return decoder
}

private func rawBase64(_ value: Data) -> String {
  value.base64EncodedString().trimmingCharacters(in: CharacterSet(charactersIn: "="))
}

@Suite("Lexicon bytes JSON")
struct LexiconBytesTests {
  @Test(arguments: [
    Data(),
    Data("plain UTF-8".utf8),
    Data([0x00, 0xFF, 0x10, 0x80]),
  ])
  func encodesDataAsBytesObject(_ value: Data) throws {
    let encoded = try xrpcEncoder().encode(value)
    let expected = #"{"$bytes":"\#(rawBase64(value))"}"#

    #expect(String(decoding: encoded, as: UTF8.self) == expected)
  }

  @Test(arguments: [
    Data(),
    Data("round trip".utf8),
    Data([0x00, 0x01, 0xFE, 0xFF]),
  ])
  func bytesObjectRoundTrips(_ value: Data) throws {
    let encoded = try xrpcEncoder().encode(value)
    let decoded = try xrpcDecoder().decode(Data.self, from: encoded)

    #expect(decoded == value)
  }

  @Test func decodesLegacyBareBase64String() throws {
    let value = Data([0xCA, 0xFE, 0xBA, 0xBE])
    let json = Data(#""yv66vg==""#.utf8)

    #expect(try xrpcDecoder().decode(Data.self, from: json) == value)
  }

  @Test(arguments: [
    #"{"$bytes":"not base64"}"#,
    #"{"other":"AQI="}"#,
    #"{"$bytes":12}"#,
  ])
  func rejectsInvalidBytesObjects(_ json: String) {
    #expect(throws: DecodingError.self) {
      try xrpcDecoder().decode(Data.self, from: Data(json.utf8))
    }
  }

  @Test func generatedRecordUsesCanonicalBytesForm() throws {
    let record = GeneratedBytesRecord(tag: Data([0x01, 0x02, 0x03]))
    let encoded = try xrpcEncoder().encode(record)

    #expect(
      String(decoding: encoded, as: UTF8.self)
        == #"{"$type":"sh.tangled.repo.artifact","tag":{"$bytes":"AQID"}}"#
    )
    #expect(try xrpcDecoder().decode(GeneratedBytesRecord.self, from: encoded) == record)
  }

  @Test func constraintsUseDecodedByteCount() throws {
    let decoder = xrpcDecoder()
    let valid = try decoder.decode(
      ConstrainedBytesRecord.self,
      from: Data(#"{"tag":{"$bytes":"AQI="}}"#.utf8)
    )

    #expect(valid.tag == Data([0x01, 0x02]))
    #expect(throws: DecodingError.self) {
      try decoder.decode(
        ConstrainedBytesRecord.self,
        from: Data(#"{"tag":{"$bytes":"AQ=="}}"#.utf8)
      )
    }
    #expect(throws: DecodingError.self) {
      try decoder.decode(
        ConstrainedBytesRecord.self,
        from: Data(#"{"tag":{"$bytes":"AQIDBAU="}}"#.utf8)
      )
    }
  }

  @Test func xrpcRequestAndResponseUseCanonicalBytesForm() async throws {
    let responseJSON =
      #"{"$type":"sh.tangled.repo.artifact","tag":{"$bytes":"BAUG"}}"#
    let recorder = BytesRequestRecorder()
    let client = BytesTestClient(
      responseData: Data(responseJSON.utf8),
      recorder: recorder
    )

    let response = try await client.call(
      BytesProcedure.self,
      input: GeneratedBytesRecord(tag: Data([0x01, 0x02, 0x03]))
    )

    let request = try #require(recorder.lastRequest)
    let body = try #require(request.body)
    let requestObject = try #require(
      JSONSerialization.jsonObject(with: body) as? [String: Any]
    )
    let requestTag = try #require(requestObject["tag"] as? [String: String])
    #expect(requestObject["$type"] as? String == "sh.tangled.repo.artifact")
    #expect(requestTag == ["$bytes": "AQID"])
    #expect(response.tag == Data([0x04, 0x05, 0x06]))
  }

  @Test func rawBinaryBodiesBypassJSONCoding() async throws {
    let requestData = Data([0x00, 0xFF, 0x01])
    let responseData = Data([0x02, 0xFE, 0x03])
    let recorder = BytesRequestRecorder()
    let client = BytesTestClient(responseData: responseData, recorder: recorder)

    let response = try await client.call(RawBinaryProcedure.self, input: requestData)

    #expect(recorder.lastRequest?.body == requestData)
    #expect(response == responseData)
  }

  @Test func cidStillUsesLinkObject() throws {
    let json =
      #"{"$link":"bafkreibxn7ww5xcnkgwii3cndu46ike6reqllouvapfevfrxscpm3ovveq"}"#
    let link = try xrpcDecoder().decode(LexLink.self, from: Data(json.utf8))

    #expect(try String(decoding: xrpcEncoder().encode(link), as: UTF8.self) == json)
  }
}
