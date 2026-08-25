import Foundation

// `ATProtoCrypto` only encodes base64url — reading a token back is the job of the
// introspection side, in `SwiftAtproto` — so the tests decode their own.
func decodedSegment(_ jwt: String, _ index: Int) -> Data? {
  let segments = jwt.split(separator: ".", omittingEmptySubsequences: false)
  guard segments.indices.contains(index) else { return nil }
  var base64 = segments[index].replacingOccurrences(of: "-", with: "+")
    .replacingOccurrences(of: "_", with: "/")
  base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
  return Data(base64Encoded: base64)
}

struct UndecodableSegment: Error {
  let index: Int
}

// A `Decodable` struct ignores any member it does not name, so the member sets
// are checked separately. This reads the names alone rather than decoding the
// values as `Any`, which would compare JSON numbers through a box whose type
// differs between Darwin and swift-corelibs-foundation.
func memberNames(of jwt: String, _ index: Int) throws -> [String] {
  guard let data = decodedSegment(jwt, index) else { throw UndecodableSegment(index: index) }
  return try JSONDecoder().decode(MemberNames.self, from: data).sorted
}

private struct MemberNames: Decodable {
  let sorted: [String]

  private struct AnyKey: CodingKey {
    let stringValue: String
    var intValue: Int? { nil }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { nil }
  }

  init(from decoder: any Decoder) throws {
    sorted = try decoder.container(keyedBy: AnyKey.self).allKeys.map(\.stringValue).sorted()
  }
}
