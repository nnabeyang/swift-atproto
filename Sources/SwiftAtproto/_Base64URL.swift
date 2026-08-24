import Foundation

// base64url is the only encoding JOSE spells its segments in, and this module had no decoder for
// it. Neither of the two nearby candidates fits:
//
//   - the base64 in `JSONEncoder+XRPC.swift` uses the standard alphabet the Lexicon `bytes` type is
//     written in, which a JOSE segment must not carry;
//   - `Base64` reaches the build graph transitively through `CID`, but it is not a declared
//     dependency of this target, and its `.url` variant is padding-tolerant and decodes `+` and `/`
//     as well — the two things RFC 7515 forbids a segment to contain.

/// Decodes an unpadded URL-safe base64 string, or `nil` when `string` is not one.
///
/// Strict on purpose. JOSE writes every segment with the URL-safe alphabet and no padding, so `+`,
/// `/`, and `=` are rejected rather than quietly accepted: a token that only this decoder can read
/// is a token no peer can.
func base64URLDecoded(_ string: some StringProtocol) -> Data? {
  var standard = ""
  standard.reserveCapacity(string.utf8.count + 2)
  for byte in string.utf8 {
    switch byte {
    case UInt8(ascii: "-"):
      standard.append("+")
    case UInt8(ascii: "_"):
      standard.append("/")
    case let byte where isAlphanumeric(byte):
      standard.append(Character(UnicodeScalar(byte)))
    default:
      return nil
    }
  }

  // A base64 quantum is 2, 3, or 4 characters wide; a remainder of 1 encodes no whole byte and so
  // cannot be the tail of anything that was encoded.
  switch standard.utf8.count % 4 {
  case 0: break
  case 2: standard += "=="
  case 3: standard += "="
  default: return nil
  }
  return Data(base64Encoded: standard)
}
