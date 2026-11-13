#if !canImport(Darwin)
  import FoundationEssentials
#else
  import Foundation
#endif

/// A bare item of an RFC 9651 Structured Field.
enum StructuredBareItem: Hashable, Sendable {
  case integer(Int64)
  /// A decimal in thousandths, the precision RFC 9651 allows, so that equal
  /// values compare equal and serialize alike.
  case decimal(thousandths: Int64)
  case string(String)
  case token(String)
  case bytes(Data)
  case boolean(Bool)
  /// Seconds since the Unix epoch.
  case date(Int64)
  case displayString(String)
}

/// Keys with values, in the order the keys first appeared.
///
/// RFC 9651 §4.2 lets a later member or parameter with the same key overwrite
/// an earlier one's value while keeping its position, so an array of pairs or a
/// Swift dictionary alone would serialize differently from what was parsed.
struct StructuredOrderedMap<Value: Hashable & Sendable>: Hashable, Sendable {
  private(set) var entries: [(key: String, value: Value)] = []

  init() {}

  init(_ entries: [(key: String, value: Value)]) {
    for (key, value) in entries { self[key] = value }
  }

  subscript(key: String) -> Value? {
    get { entries.first { $0.key == key }?.value }
    set {
      if let index = entries.firstIndex(where: { $0.key == key }) {
        if let newValue {
          entries[index].value = newValue
        } else {
          entries.remove(at: index)
        }
      } else if let newValue {
        entries.append((key: key, value: newValue))
      }
    }
  }

  var keys: [String] { entries.map(\.key) }
  var isEmpty: Bool { entries.isEmpty }
  var count: Int { entries.count }

  static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.entries.elementsEqual(rhs.entries) { $0.key == $1.key && $0.value == $1.value }
  }

  func hash(into hasher: inout Hasher) {
    for entry in entries {
      hasher.combine(entry.key)
      hasher.combine(entry.value)
    }
  }
}

typealias StructuredParameters = StructuredOrderedMap<StructuredBareItem>

/// A bare item with its parameters.
struct StructuredItem: Hashable, Sendable {
  var bareItem: StructuredBareItem
  var parameters: StructuredParameters

  init(_ bareItem: StructuredBareItem, parameters: StructuredParameters = .init()) {
    self.bareItem = bareItem
    self.parameters = parameters
  }
}

/// An inner list with its parameters, such as the covered components and
/// signature parameters of an RFC 9421 signature.
struct StructuredInnerList: Hashable, Sendable {
  var items: [StructuredItem]
  var parameters: StructuredParameters

  init(_ items: [StructuredItem], parameters: StructuredParameters = .init()) {
    self.items = items
    self.parameters = parameters
  }
}

/// A member of a Dictionary or List: an item or an inner list.
enum StructuredMember: Hashable, Sendable {
  case item(StructuredItem)
  case innerList(StructuredInnerList)
}

/// An RFC 9651 §3.2 Dictionary, parsed and serialized as §4.2.2 and §4.1.2
/// describe.
///
/// Serializing what was parsed gives the canonical form RFC 9421 §2.1.1 signs
/// for a field with the `sf` flag: whitespace, padding, and duplicate keys are
/// normalized away.
struct StructuredDictionary: Hashable, Sendable {
  var members: StructuredOrderedMap<StructuredMember>

  init(_ members: StructuredOrderedMap<StructuredMember> = .init()) {
    self.members = members
  }

  subscript(key: String) -> StructuredMember? { members[key] }

  /// The Dictionary in `input`, or `nil` when it is not one.
  static func parse(_ input: String) -> Self? {
    var parser = StructuredFieldParser(input)
    return parser.dictionary().map(Self.init)
  }

  var serialized: String {
    members.entries.map { key, member in
      switch member {
      case .item(let item) where item.bareItem == .boolean(true):
        // A true member is written as its key alone (§4.1.2).
        key + StructuredFieldSerializer.parameters(item.parameters)
      case .item(let item):
        key + "=" + StructuredFieldSerializer.item(item)
      case .innerList(let list):
        key + "=" + StructuredFieldSerializer.innerList(list)
      }
    }
    .joined(separator: ", ")
  }
}

enum StructuredFieldSerializer {
  static func innerList(_ list: StructuredInnerList) -> String {
    "(" + list.items.map(item).joined(separator: " ") + ")" + parameters(list.parameters)
  }

  static func item(_ item: StructuredItem) -> String {
    bareItem(item.bareItem) + parameters(item.parameters)
  }

  static func parameters(_ parameters: StructuredParameters) -> String {
    parameters.entries.map { key, value in
      value == .boolean(true) ? ";" + key : ";" + key + "=" + bareItem(value)
    }
    .joined()
  }

  static func bareItem(_ item: StructuredBareItem) -> String {
    switch item {
    case .integer(let value):
      return String(value)
    case .decimal(let thousandths):
      let magnitude = thousandths.magnitude
      var fraction = String(magnitude % 1000)
      fraction = String(repeating: "0", count: 3 - fraction.count) + fraction
      // At least one fractional digit, and no trailing zeros beyond it (§4.1.5).
      while fraction.count > 1, fraction.hasSuffix("0") { fraction.removeLast() }
      return (thousandths < 0 ? "-" : "") + String(magnitude / 1000) + "." + fraction
    case .string(let value):
      var output = "\""
      for character in value {
        if character == "\\" || character == "\"" { output.append("\\") }
        output.append(character)
      }
      return output + "\""
    case .token(let value):
      return value
    case .bytes(let value):
      // Foundation writes padded base64, as §4.1.8 requires.
      return ":" + value.base64EncodedString() + ":"
    case .boolean(let value):
      return value ? "?1" : "?0"
    case .date(let value):
      return "@" + String(value)
    case .displayString(let value):
      var output = "%\""
      for byte in value.utf8 {
        if byte == UInt8(ascii: "%") || byte == UInt8(ascii: "\"") || !(0x20...0x7e).contains(byte) {
          output += "%" + String(byte >> 4, radix: 16) + String(byte & 0x0f, radix: 16)
        } else {
          output.append(Character(Unicode.Scalar(byte)))
        }
      }
      return output + "\""
    }
  }
}

/// RFC 9651 §4.2 over the bytes of a field value.
struct StructuredFieldParser {
  private var bytes: [UInt8]
  private var index = 0

  init(_ input: String) {
    bytes = Array(input.utf8)
  }

  private var current: UInt8? { index < bytes.count ? bytes[index] : nil }

  private mutating func skip(_ predicate: (UInt8) -> Bool) {
    while let byte = current, predicate(byte) { index += 1 }
  }

  private mutating func consume(_ byte: UInt8) -> Bool {
    guard current == byte else { return false }
    index += 1
    return true
  }

  /// §4.2.2, with the surrounding spaces of §4.2 removed first.
  mutating func dictionary() -> StructuredOrderedMap<StructuredMember>? {
    skip { $0 == 0x20 }
    while bytes.last == 0x20 { bytes.removeLast() }
    var members = StructuredOrderedMap<StructuredMember>()
    while current != nil {
      guard let key = key() else { return nil }
      if consume(UInt8(ascii: "=")) {
        guard let member = itemOrInnerList() else { return nil }
        members[key] = member
      } else {
        guard let parameters = parameters() else { return nil }
        members[key] = .item(StructuredItem(.boolean(true), parameters: parameters))
      }
      skip(Self.isOWS)
      guard current != nil else { return members }
      guard consume(UInt8(ascii: ",")) else { return nil }
      skip(Self.isOWS)
      // A trailing comma is not allowed.
      guard current != nil else { return nil }
    }
    return members
  }

  private mutating func itemOrInnerList() -> StructuredMember? {
    if current == UInt8(ascii: "(") {
      return innerList().map(StructuredMember.innerList)
    }
    return item().map(StructuredMember.item)
  }

  private mutating func item() -> StructuredItem? {
    guard let bare = bareItem(), let parameters = parameters() else { return nil }
    return StructuredItem(bare, parameters: parameters)
  }

  private mutating func innerList() -> StructuredInnerList? {
    guard consume(UInt8(ascii: "(")) else { return nil }
    var items: [StructuredItem] = []
    while true {
      skip { $0 == 0x20 }
      guard current != nil else { return nil }
      if consume(UInt8(ascii: ")")) {
        return parameters().map { StructuredInnerList(items, parameters: $0) }
      }
      guard let item = item() else { return nil }
      items.append(item)
      guard current == 0x20 || current == UInt8(ascii: ")") else { return nil }
    }
  }

  private mutating func parameters() -> StructuredParameters? {
    var parameters = StructuredParameters()
    while consume(UInt8(ascii: ";")) {
      skip { $0 == 0x20 }
      guard let key = key() else { return nil }
      var value = StructuredBareItem.boolean(true)
      if consume(UInt8(ascii: "=")) {
        guard let bare = bareItem() else { return nil }
        value = bare
      }
      parameters[key] = value
    }
    return parameters
  }

  private mutating func key() -> String? {
    guard let first = current, Self.isLowerAlpha(first) || first == UInt8(ascii: "*") else {
      return nil
    }
    let start = index
    skip {
      Self.isLowerAlpha($0) || Self.isDigit($0) || $0 == UInt8(ascii: "_")
        || $0 == UInt8(ascii: "-") || $0 == UInt8(ascii: ".") || $0 == UInt8(ascii: "*")
    }
    return String(decoding: bytes[start..<index], as: UTF8.self)
  }

  private mutating func bareItem() -> StructuredBareItem? {
    guard let byte = current else { return nil }
    switch byte {
    case UInt8(ascii: "-"), UInt8(ascii: "0")...UInt8(ascii: "9"): return number()
    case UInt8(ascii: "\""): return string()
    case UInt8(ascii: ":"): return byteSequence()
    case UInt8(ascii: "?"): return boolean()
    case UInt8(ascii: "@"): return date()
    case UInt8(ascii: "%"): return displayString()
    case UInt8(ascii: "*"), UInt8(ascii: "A")...UInt8(ascii: "Z"), UInt8(ascii: "a")...UInt8(ascii: "z"):
      return token()
    default: return nil
    }
  }

  /// §4.2.4.
  private mutating func number() -> StructuredBareItem? {
    let negative = consume(UInt8(ascii: "-"))
    let integerStart = index
    skip(Self.isDigit)
    let integerDigits = index - integerStart
    guard integerDigits > 0 else { return nil }
    let integerPart = Int64(String(decoding: bytes[integerStart..<index], as: UTF8.self))
    guard consume(UInt8(ascii: ".")) else {
      guard integerDigits <= 15, let integerPart else { return nil }
      return .integer(negative ? -integerPart : integerPart)
    }
    guard integerDigits <= 12, let integerPart else { return nil }
    let fractionStart = index
    skip(Self.isDigit)
    let fraction = String(decoding: bytes[fractionStart..<index], as: UTF8.self)
    guard (1...3).contains(fraction.count), let fractionValue = Int64(fraction) else { return nil }
    let scale: Int64 = fraction.count == 1 ? 100 : fraction.count == 2 ? 10 : 1
    let thousandths = integerPart * 1000 + fractionValue * scale
    return .decimal(thousandths: negative ? -thousandths : thousandths)
  }

  /// §4.2.5.
  private mutating func string() -> StructuredBareItem? {
    guard consume(UInt8(ascii: "\"")) else { return nil }
    var output: [UInt8] = []
    while let byte = current {
      index += 1
      switch byte {
      case UInt8(ascii: "\\"):
        guard let escaped = current, escaped == UInt8(ascii: "\\") || escaped == UInt8(ascii: "\"")
        else { return nil }
        index += 1
        output.append(escaped)
      case UInt8(ascii: "\""):
        return .string(String(decoding: output, as: UTF8.self))
      case 0x20...0x7e:
        output.append(byte)
      default:
        return nil
      }
    }
    return nil
  }

  /// §4.2.6.
  private mutating func token() -> StructuredBareItem? {
    let start = index
    index += 1
    skip { Self.isTChar($0) || $0 == UInt8(ascii: ":") || $0 == UInt8(ascii: "/") }
    return .token(String(decoding: bytes[start..<index], as: UTF8.self))
  }

  /// §4.2.7.
  private mutating func byteSequence() -> StructuredBareItem? {
    guard consume(UInt8(ascii: ":")) else { return nil }
    let start = index
    skip {
      Self.isAlpha($0) || Self.isDigit($0) || $0 == UInt8(ascii: "+") || $0 == UInt8(ascii: "/")
        || $0 == UInt8(ascii: "=")
    }
    var encoded = String(decoding: bytes[start..<index], as: UTF8.self)
    guard consume(UInt8(ascii: ":")) else { return nil }
    // Parsing should not fail when `=` padding is absent (§4.2.7).
    encoded += String(repeating: "=", count: (4 - encoded.count % 4) % 4)
    guard let data = Data(base64Encoded: encoded) else { return nil }
    return .bytes(data)
  }

  /// §4.2.8.
  private mutating func boolean() -> StructuredBareItem? {
    guard consume(UInt8(ascii: "?")) else { return nil }
    if consume(UInt8(ascii: "1")) { return .boolean(true) }
    if consume(UInt8(ascii: "0")) { return .boolean(false) }
    return nil
  }

  /// §4.2.9.
  private mutating func date() -> StructuredBareItem? {
    guard consume(UInt8(ascii: "@")), case .integer(let seconds) = number() else { return nil }
    return .date(seconds)
  }

  /// §4.2.10.
  private mutating func displayString() -> StructuredBareItem? {
    guard consume(UInt8(ascii: "%")), consume(UInt8(ascii: "\"")) else { return nil }
    var output: [UInt8] = []
    while let byte = current {
      index += 1
      switch byte {
      case UInt8(ascii: "%"):
        guard index + 1 < bytes.count,
          let high = Self.lowerHexValue(bytes[index]), let low = Self.lowerHexValue(bytes[index + 1])
        else { return nil }
        index += 2
        output.append(high << 4 | low)
      case UInt8(ascii: "\""):
        guard let value = String(bytes: output, encoding: .utf8) else { return nil }
        return .displayString(value)
      case 0x20...0x7e:
        output.append(byte)
      default:
        return nil
      }
    }
    return nil
  }

  private static func isOWS(_ byte: UInt8) -> Bool { byte == 0x20 || byte == 0x09 }

  private static func isLowerAlpha(_ byte: UInt8) -> Bool {
    byte >= UInt8(ascii: "a") && byte <= UInt8(ascii: "z")
  }

  private static func isAlpha(_ byte: UInt8) -> Bool {
    isLowerAlpha(byte) || (byte >= UInt8(ascii: "A") && byte <= UInt8(ascii: "Z"))
  }

  private static func isDigit(_ byte: UInt8) -> Bool {
    byte >= UInt8(ascii: "0") && byte <= UInt8(ascii: "9")
  }

  /// `tchar` of RFC 9110 §5.6.2.
  private static func isTChar(_ byte: UInt8) -> Bool {
    isAlpha(byte) || isDigit(byte) || "!#$%&'*+-.^_`|~".utf8.contains(byte)
  }

  private static func lowerHexValue(_ byte: UInt8) -> UInt8? {
    switch byte {
    case UInt8(ascii: "0")...UInt8(ascii: "9"): byte - UInt8(ascii: "0")
    case UInt8(ascii: "a")...UInt8(ascii: "f"): byte - UInt8(ascii: "a") + 10
    default: nil
    }
  }
}
