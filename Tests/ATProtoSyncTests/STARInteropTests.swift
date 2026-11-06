import Foundation
import SwiftAtproto
import SwiftCbor
import Testing

@testable import ATProtoSync

// The interop vectors of the STAR specification (see THIRD_PARTY_NOTICES.md).
// They exercise the framing of any profile, where keys may be empty, repeated,
// or unsorted, so they run through `STARReader` and a check of the metadata
// that every STAR archive needs: a canonical DRISL map with a text `$type`.
// The rules of the `atproto-space-repo` profile are tested in
// PermissionedRepoSTARTests.
@Suite("STAR interop vectors")
struct STARInteropTests {
  @Test("valid archives parse to their decoded contents", arguments: try ValidFixture.load())
  func valid(_ fixture: ValidFixture) async throws {
    let archive = try await Self.parse(Data(hex: fixture.starHex))
    #expect(archive.metadata == (try fixture.metadata))
    #expect(archive.pairs.map(\.key) == fixture.pairs.map(\.key))
    #expect(archive.pairs.map(\.value) == fixture.pairs.map(\.value))
  }

  @Test("invalid archives fail to parse", arguments: try InvalidFixture.load())
  func invalid(_ fixture: InvalidFixture) async throws {
    await #expect(throws: (any Error).self) {
      _ = try await Self.parse(Data(hex: fixture.starHex))
    }
  }

  /// Reads a whole archive with the default limits.
  private static func parse(_ bytes: Data) async throws -> (
    metadata: Data, pairs: [(key: Data, value: Data)]
  ) {
    let limits = RepoVerificationLimits()
    let reader = STARReader(body: XRPCBody(bytes))
    try await reader.readMagic()
    let metadata = try await reader.readFrame(maximumBytes: limits.maximumCommitBytes)
    _ = try drislDecoder(
      maximumNestingDepth: limits.maximumNestingDepth,
      maximumContainerElements: limits.maximumCommitBytes,
      maximumStringBytes: limits.maximumCommitBytes
    ).decode(Metadata.self, from: metadata)
    var pairs: [(key: Data, value: Data)] = []
    while try await reader.readControlByte() {
      let key = try await reader.readFrame(maximumBytes: limits.maximumRecordPathBytes)
      let value = try await reader.readFrame(maximumBytes: limits.maximumRecordBytes)
      pairs.append((key, value))
    }
    return (metadata, pairs)
  }

  /// Any DRISL map with a text `$type`. Decoding scans the whole map, so one
  /// that isn't canonical is rejected too.
  private struct Metadata: Decodable {
    init(from decoder: any Decoder) throws {
      let container = try decoder.container(keyedBy: AnyCodingKeys.self)
      _ = try container.decode(String.self, forKey: AnyCodingKeys(stringValue: "$type"))
    }
  }

  struct ValidFixture: Decodable, Sendable, CustomTestStringConvertible {
    let comment: String
    let starHex: String
    let decoded: Decoded

    struct Decoded: Decodable, Sendable {
      let meta: MetadataValue
      let pairs: [Pair]
    }

    struct Pair: Decodable, Sendable {
      let keyHex: String
      let valueHex: String

      private enum CodingKeys: String, CodingKey {
        case keyHex = "key_hex"
        case valueHex = "value_hex"
      }
    }

    private enum CodingKeys: String, CodingKey {
      case comment, decoded
      case starHex = "star_hex"
    }

    var testDescription: String { comment }

    /// The canonical DRISL encoding of the expected metadata, which equals
    /// the archive's metadata byte for byte when their contents are the same.
    var metadata: Data {
      get throws { try CborEncoder(options: .lexicographicallySortedMapKeys).encode(decoded.meta) }
    }

    var pairs: [(key: Data, value: Data)] {
      decoded.pairs.map { (Data(hex: $0.keyHex), Data(hex: $0.valueHex)) }
    }

    static func load() throws -> [Self] {
      try fixtures("valid-star-fixtures.json")
    }
  }

  struct InvalidFixture: Decodable, Sendable, CustomTestStringConvertible {
    let comment: String
    let starHex: String

    private enum CodingKeys: String, CodingKey {
      case comment
      case starHex = "star_hex"
    }

    var testDescription: String { comment }

    static func load() throws -> [Self] {
      try fixtures("invalid-star-fixtures.json")
    }
  }

  private static func fixtures<Fixture: Decodable>(_ name: String) throws -> [Fixture] {
    guard
      let url = Bundle.module.url(
        forResource: name, withExtension: nil, subdirectory: "Fixtures/STARInterop")
    else {
      throw CocoaError(.fileNoSuchFile, userInfo: [NSFilePathErrorKey: name])
    }
    return try JSONDecoder().decode([Fixture].self, from: Data(contentsOf: url))
  }

  /// A metadata value as the fixtures write it in JSON: the vectors use text,
  /// integers, arrays, and maps.
  enum MetadataValue: Codable, Sendable {
    case text(String)
    case integer(Int)
    case array([MetadataValue])
    case map([String: MetadataValue])

    init(from decoder: any Decoder) throws {
      let container = try decoder.singleValueContainer()
      if let text = try? container.decode(String.self) {
        self = .text(text)
      } else if let integer = try? container.decode(Int.self) {
        self = .integer(integer)
      } else if let array = try? container.decode([MetadataValue].self) {
        self = .array(array)
      } else if let map = try? container.decode([String: MetadataValue].self) {
        self = .map(map)
      } else {
        throw DecodingError.dataCorruptedError(
          in: container, debugDescription: "Expected text, an integer, an array, or a map.")
      }
    }

    func encode(to encoder: any Encoder) throws {
      var container = encoder.singleValueContainer()
      switch self {
      case .text(let text): try container.encode(text)
      case .integer(let integer): try container.encode(integer)
      case .array(let array): try container.encode(array)
      case .map(let map): try container.encode(map)
      }
    }
  }
}
