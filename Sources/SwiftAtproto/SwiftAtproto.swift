import CID
import Foundation

public struct EmptyResponse: Codable {}

public protocol ATProtoRecord: Codable, Sendable {
  static var nsId: String { get }
}

enum TypeCodingKeys: String, CodingKey {
  case type = "$type"
}

public protocol UnknownATPValueProtocol: Codable, Sendable {
  static func record(_: any ATProtoRecord) -> Self
  static func any(_: any Codable & Sendable) -> Self
  var type: String? { get }
  var val: Codable & Sendable { get }
  static var allTypes: [String: any ATProtoRecord.Type] { get }
  @available(*, deprecated, message: "Use `static func record(_:)` instead — this initializer is deprecated and will be removed in a future release.")
  init(typeName: String, val: any Codable & Sendable)
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

  @available(*, deprecated, message: "Use `static func record(_:)` instead — this initializer is deprecated and will be removed in a future release.")
  public init(typeName: String, val: any Codable & Sendable) {
    switch val {
    case let val as (any ATProtoRecord):
      self = .record(val)
    default:
      self = .any(AnyCodable(val))
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

public typealias LexLink = CID
extension CID: @unchecked @retroactive Sendable {}

extension LexLink: @retroactive Codable {
  static func dataEncodingStrategy(data: Data, encoder: any Encoder) throws {
    let cid = try CID(data[1...])
    var container = encoder.container(keyedBy: LexLink.CodingKeys.self)
    try container.encode(cid.toBaseEncodedString, forKey: .link)
  }

  enum CodingKeys: String, CodingKey {
    case link = "$link"
  }

  public init(from decoder: Decoder) throws {
    do {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      let link = try container.decode(String.self, forKey: .link)
      self = try CID(link)
    } catch {
      let container = try decoder.singleValueContainer()
      let bytes = try [UInt8](container.decode(Data.self))
      guard bytes[0] == 0 else {
        throw error
      }
      self = try CID(Data(bytes[1...]))
    }
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    var bytes: [UInt8] = [0]
    bytes.append(contentsOf: rawBuffer)
    try container.encode(Data(bytes))
  }
}

public struct LexBlob: Codable, Sendable {
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

public enum ParamElement: Encodable {
  case string(String?)
  case bool(Bool?)
  case integer(Int?)
  case array([any Encodable]?)
  case unknown((any UnknownATPValueProtocol)?)

  public func encode(to encoder: Encoder) throws {
    switch self {
    case .string(let value):
      try value.encode(to: encoder)
    case .bool(let value):
      try value.encode(to: encoder)
    case .integer(let value):
      try value.encode(to: encoder)
    case .array(let values):
      if let values {
        var container = encoder.unkeyedContainer()
        for value in values {
          try container.encode(value)
        }
      }
    case .unknown(let value):
      try value?.encode(to: encoder)
    }
  }
}

public final class Parameters: Encodable, ExpressibleByDictionaryLiteral {
  private let dictionary: [String: ParamElement]
  public init(dictionary: [String: ParamElement]) {
    self.dictionary = dictionary
  }

  public func encode(to encoder: Encoder) throws {
    let d = dictionary.filter {
      switch $1 {
      case .string(let v):
        v != nil
      case .bool(let v):
        v != nil
      case .integer(let v):
        v != nil
      case .array(let v):
        v != nil
      case .unknown(let v):
        v != nil
      }
    }
    try d.encode(to: encoder)
  }

  public typealias Key = String
  public typealias Value = ParamElement
  public required convenience init(dictionaryLiteral elements: (String, ParamElement)...) {
    let dictionary = [String: ParamElement](elements, uniquingKeysWith: { l, _ in l })
    self.init(dictionary: dictionary)
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
