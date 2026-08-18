import CID
import Foundation
import Multibase
import Multicodec
import Multihash
import SwiftCbor

public struct EmptyResponse: Codable, Sendable, Hashable {
  public init() {}
}

public protocol ATProtoRecord: Codable, Sendable, Hashable {
  static var nsId: String { get }
}

enum TypeCodingKeys: String, CodingKey {
  case type = "$type"
}

public protocol XRPCRequest: Sendable {
  associatedtype ResponseBody: Codable & Sendable & Hashable
  associatedtype Error: XRPCError

  static var id: String { get }
}

extension XRPCRequest {
  public static func requiredRpcLxm() -> String { id }
}

public protocol XRPCQuery: XRPCRequest {
  associatedtype Input: XRPCQueryInput
}

public protocol XRPCQueryInput: Sendable & Hashable {
  associatedtype Query: XRPCInputQuery

  var query: Query { get }
}

public protocol XRPCInputQuery: Sendable, Hashable {
  var asParameters: Parameters? { get }
}

public protocol XRPCProcedure: XRPCRequest {
  associatedtype RequestBody: Codable & Sendable & Hashable
  static var contentType: String { get }
}

public protocol UnknownATPValueProtocol: Codable, Sendable, Hashable {
  static func record(_: any ATProtoRecord) -> Self
  static func any(_: any Codable & Sendable & Hashable) -> Self
  var type: String? { get }
  var val: any Codable & Hashable & Sendable { get }
  static var allTypes: [String: any ATProtoRecord.Type] { get }
}

extension UnknownATPValueProtocol {
  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: TypeCodingKeys.self)
    if let typeName = try container.decodeIfPresent(String.self, forKey: .type) {
      guard let type = Self.allTypes[typeName] else {
        self = try .record(UnknownRecord(from: decoder))
        return
      }
      self = try .record(type.init(from: decoder))
    } else {
      let object = try AnyCodable(from: decoder)
      if let object = object.base as? DIDDocument {
        self = .any(object)
      } else {
        self = .any(object)
      }
    }
  }

  public func hash(into hasher: inout Hasher) {
    hasher.combine(val)
  }

  public static func == (lhs: Self, rhs: Self) -> Bool {
    if Swift.type(of: lhs.val) != Swift.type(of: rhs.val) { return false }
    switch (lhs.val, rhs.val) {
    case (let left as AnyHashable, let right as AnyHashable):
      return left == right
    default:
      return false
    }
  }

  public func encode(to encoder: any Encoder) throws {
    if let type = type {
      var container = encoder.container(keyedBy: TypeCodingKeys.self)
      try container.encode(type, forKey: .type)
    }
    try val.encode(to: encoder)
  }
}

extension String {
  func trim(prefix: String) -> String {
    guard hasPrefix(prefix) else { return self }
    return String(dropFirst(prefix.count))
  }

  var titleCased: String {
    var prev = Character(" ")
    return String(
      map {
        if prev.isWhitespace {
          prev = $0
          return Character($0.uppercased())
        }
        prev = $0
        return $0
      })
  }

  func camelCased() -> String {
    guard !isEmpty else { return "" }
    let words = components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
    let first = words.first!.lowercased()
    let rest = words.dropFirst().map(\.capitalized)
    return ([first] + rest).joined()
  }
}

public struct LexLink: Sendable, Hashable, Codable, CborCodable, CustomStringConvertible {
  public var cid: CID

  public init(_ cid: CID) {
    self.cid = cid
  }

  public init(_ s: String) throws {
    self.cid = try CID(s)
  }

  public init(_ data: Data, base: BaseEncoding? = nil) throws {
    self.cid = try CID(data, base: base)
  }

  public init(_ bytes: [UInt8], base: BaseEncoding? = nil) throws {
    self.cid = try CID(bytes, base: base)
  }

  public var toBaseEncodedString: String { cid.toBaseEncodedString }

  public var description: String { cid.description }

  public var tag: UInt64 { 42 }

  enum CodingKeys: String, CodingKey {
    case link = "$link"
  }

  static func dataEncodingStrategy(data: Data, encoder: any Encoder) throws {
    let cid = try CID(data[1...])
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(cid.toBaseEncodedString, forKey: .link)
  }

  public init(from decoder: Decoder) throws {
    do {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      let link = try container.decode(String.self, forKey: .link)
      self.cid = try CID(link)
    } catch {
      let container = try decoder.singleValueContainer()
      let bytes = try [UInt8](container.decode(Data.self))
      guard bytes[0] == 0 else {
        throw error
      }
      self.cid = try CID(Data(bytes[1...]))
    }
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    var bytes: [UInt8] = [0]
    bytes.append(contentsOf: cid.rawBuffer)
    try container.encode(Data(bytes))
  }

  // MARK: Deprecated CID forwards (scheduled for removal in 0.44.0)

  @available(*, deprecated, message: "Access via lexLink.cid.version. Scheduled for removal in 0.44.0.")
  public var version: CIDVersion { cid.version }

  @available(*, deprecated, message: "Access via lexLink.cid.codec. Scheduled for removal in 0.44.0.")
  public var codec: Codecs { cid.codec }

  @available(*, deprecated, message: "Access via lexLink.cid.multibase. Scheduled for removal in 0.44.0.")
  public var multibase: BaseEncoding { cid.multibase }

  @available(*, deprecated, message: "Access via lexLink.cid.multihash. Scheduled for removal in 0.44.0.")
  public var multihash: Multihash { cid.multihash }

  @available(*, deprecated, message: "Access via lexLink.cid.code. Scheduled for removal in 0.44.0.")
  public var code: Int { cid.code }

  @available(*, deprecated, message: "Access via lexLink.cid.rawBuffer. Scheduled for removal in 0.44.0.")
  public var rawBuffer: [UInt8] { cid.rawBuffer }

  @available(*, deprecated, message: "Access via lexLink.cid.rawData. Scheduled for removal in 0.44.0.")
  public var rawData: Data { cid.rawData }

  @available(*, deprecated, message: "Access via lexLink.cid.prefix. Scheduled for removal in 0.44.0.")
  public var prefix: [UInt8] { cid.prefix }

  @available(*, deprecated, message: "Access via lexLink.cid.toBaseEncodedString(_:). Scheduled for removal in 0.44.0.")
  public func toBaseEncodedString(_ base: BaseEncoding) throws -> String { try cid.toBaseEncodedString(base) }

  @available(*, deprecated, message: "Access via lexLink.cid.string(base:). Scheduled for removal in 0.44.0.")
  public func string(base: BaseEncoding) throws -> String { try cid.string(base: base) }

  @available(*, deprecated, message: "Use LexLink(lexLink.cid.convertedToV1()). Scheduled for removal in 0.44.0.")
  public func convertedToV1() -> LexLink { LexLink(cid.convertedToV1()) }

  @available(*, deprecated, message: "Use LexLink(try lexLink.cid.convertedToV0()). Scheduled for removal in 0.44.0.")
  public func convertedToV0() throws -> LexLink { try LexLink(cid.convertedToV0()) }

  @available(*, deprecated, message: "Mutate lexLink.cid directly. Scheduled for removal in 0.44.0.")
  public mutating func toV1() { cid.toV1() }

  @available(*, deprecated, message: "Mutate lexLink.cid directly. Scheduled for removal in 0.44.0.")
  public mutating func toV0() throws { try cid.toV0() }

  @available(*, deprecated, message: "Use LexLink(try CID(v0WithMultihash:)). Scheduled for removal in 0.44.0.")
  public init(v0WithMultihash multihash: [UInt8]) throws {
    self.cid = try CID(v0WithMultihash: multihash)
  }

  @available(*, deprecated, message: "Use LexLink(try CID(v0WithMultihash:)). Scheduled for removal in 0.44.0.")
  public init(v0WithMultihash multihash: Data) throws {
    self.cid = try CID(v0WithMultihash: multihash)
  }

  @available(*, deprecated, message: "Use LexLink(try CID(v0WithMultihash:)). Scheduled for removal in 0.44.0.")
  public init(v0WithMultihash multihash: Multihash) throws {
    self.cid = try CID(v0WithMultihash: multihash)
  }

  @available(*, deprecated, message: "Use LexLink(try CID(version:codec:hash:)). Scheduled for removal in 0.44.0.")
  public init(version: CIDVersion, codec: Codecs, hash: String) throws {
    self.cid = try CID(version: version, codec: codec, hash: hash)
  }

  @available(*, deprecated, message: "Use LexLink(try CID(version:codec:hash:)). Scheduled for removal in 0.44.0.")
  public init(version: CIDVersion, codec: Codecs, hash: Data) throws {
    self.cid = try CID(version: version, codec: codec, hash: hash)
  }

  @available(*, deprecated, message: "Use LexLink(try CID(version:codec:hash:)). Scheduled for removal in 0.44.0.")
  public init(version: CIDVersion, codec: Codecs, hash: [UInt8]) throws {
    self.cid = try CID(version: version, codec: codec, hash: hash)
  }

  @available(*, deprecated, message: "Use LexLink(try CID(version:codec:multihash:)). Scheduled for removal in 0.44.0.")
  public init(version: CIDVersion, codec: Codecs, multihash: Multihash) throws {
    self.cid = try CID(version: version, codec: codec, multihash: multihash)
  }

  @available(*, deprecated, message: "Use LexLink(try CID(version:codec:content:hashedWith:customByteLength:)). Scheduled for removal in 0.44.0.")
  public init(
    version: CIDVersion, codec: Codecs, content: [UInt8], hashedWith hashFunction: Codecs, customByteLength: Int? = nil
  ) throws {
    self.cid = try CID(
      version: version, codec: codec, content: content, hashedWith: hashFunction, customByteLength: customByteLength)
  }

  @available(*, deprecated, message: "Use LexLink(try CID(version:codec:content:hashedWith:customByteLength:)). Scheduled for removal in 0.44.0.")
  public init(
    version: CIDVersion, codec: Codecs, content: Data, hashedWith hashFunction: Codecs, customByteLength: Int? = nil
  ) throws {
    self.cid = try CID(
      version: version, codec: codec, content: content, hashedWith: hashFunction, customByteLength: customByteLength)
  }

  @available(*, deprecated, message: "Use LexLink(try CID(version:codec:content:hashedWith:using:customByteLength:)). Scheduled for removal in 0.44.0.")
  public init(
    version: CIDVersion, codec: Codecs, content: String, hashedWith hashFunction: Codecs,
    using encoding: String.Encoding = .utf8, customByteLength: Int? = nil
  ) throws {
    self.cid = try CID(
      version: version, codec: codec, content: content, hashedWith: hashFunction, using: encoding,
      customByteLength: customByteLength)
  }
}

public struct LexBlob: Codable, Sendable, Hashable {
  public let type = "blob"
  public let ref: LexLink
  public let mimeType: String
  public let size: UInt

  public init(original: Self, mimeType: String) {
    ref = original.ref
    self.mimeType = mimeType
    size = original.size
  }

  private enum CodingKeys: String, CodingKey {
    case type = "$type"
    case ref
    case mimeType
    case size
  }

  private enum LegacyCodingKeys: String, CodingKey {
    case cid
    case mimeType
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    if container.allKeys.contains(.ref) {
      ref = try container.decode(LexLink.self, forKey: .ref)
      mimeType = try container.decode(String.self, forKey: .mimeType)
      size = try container.decode(UInt.self, forKey: .size)
    } else {
      let container = try decoder.container(keyedBy: LegacyCodingKeys.self)
      let cid = try container.decode(String.self, forKey: .cid)
      ref = try LexLink(cid)
      mimeType = try container.decode(String.self, forKey: .mimeType)
      size = 0
    }
  }
}

public enum ParamElement {
  case string(String?)
  case bool(Bool?)
  case integer(Int?)
  case array([any CustomStringConvertible]?)
}

public final class Parameters: ExpressibleByDictionaryLiteral {
  public let dictionary: [String: ParamElement]
  public init(dictionary: [String: ParamElement]) {
    self.dictionary = dictionary
  }

  public typealias Key = String
  public typealias Value = ParamElement
  public required convenience init(dictionaryLiteral elements: (String, ParamElement)...) {
    let dictionary = [String: ParamElement](elements, uniquingKeysWith: { l, _ in l })
    self.init(dictionary: dictionary)
  }
}

extension Parameters: Sequence {
  public func makeIterator() -> Dictionary<String, ParamElement>.Iterator {
    dictionary.makeIterator()
  }
}

@inline(never)
@usableFromInline
func _abstract(
  file: StaticString = #file,
  line: UInt = #line
) -> Never {
  fatalError("Method must be overridden", file: file, line: line)
}
