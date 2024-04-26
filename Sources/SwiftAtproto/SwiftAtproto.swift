public class LexiconTypesMap {
    public static let shared = LexiconTypesMap()
    public var map = [String: Any.Type]()
    public func register(id: String, val: (some Any).Type) {
        map[id] = val
    }
}

public struct LexiconTypeDecoder: Codable {
    let typeName: String?
    public let val: Codable
    private enum CodingKeys: String, CodingKey {
        case type = "$type"
    }

    public init(typeName: String, val: any Codable) {
        self.typeName = typeName
        self.val = val
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let typeName = try container.decodeIfPresent(String.self, forKey: .type) {
            guard let type = LexiconTypesMap.shared.map[typeName] as? (any Codable.Type) else {
                fatalError(#""\#(typeName) is not registerd"#)
            }
            val = try type.init(from: decoder)
            self.typeName = typeName
        } else {
            val = try DIDDocument(from: decoder)
            typeName = nil
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(typeName, forKey: .type)
        try val.encode(to: encoder)
    }
}

public struct LexLink: Codable {
    public let link: String
    private enum CodingKeys: String, CodingKey {
        case link = "$link"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        link = try container.decode(String.self, forKey: .link)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(link, forKey: .link)
    }
}

public struct LexBlob: Codable {
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
}

public enum ParamElement: Encodable {
    case string(String?)
    case bool(Bool?)
    case integer(Int?)
    case array([any Encodable]?)
    case unknown(LexiconTypeDecoder?)

    public func encode(to encoder: Encoder) throws {
        switch self {
        case let .string(value):
            try value.encode(to: encoder)
        case let .bool(value):
            try value.encode(to: encoder)
        case let .integer(value):
            try value.encode(to: encoder)
        case let .array(values):
            if let values {
                var container = encoder.unkeyedContainer()
                for value in values {
                    try container.encode(value)
                }
            }
        case let .unknown(value):
            try value.encode(to: encoder)
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
            case let .string(v):
                v != nil
            case let .bool(v):
                v != nil
            case let .integer(v):
                v != nil
            case let .array(v):
                v != nil
            case let .unknown(v):
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
