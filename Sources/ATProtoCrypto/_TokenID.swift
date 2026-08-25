// Both JWTs this module signs carry a `jti` and want the same thing from it: a value no other
// token has used, drawn from a source an observer cannot predict. The generator lives here rather
// than on either type so that the two cannot drift apart in length or alphabet.

/// 16 random bytes as lowercase hexadecimal — 128 bits, which is what the OAuth and DPoP specs
/// ask of a nonce.
func randomHexTokenID() -> String {
  var generator = SystemRandomNumberGenerator()
  var hex = ""
  hex.reserveCapacity(32)
  for _ in 0..<16 {
    // A nibble is one hex digit, so `String(_:radix:)` — which is lowercase already — needs no
    // padding, and rendering the two halves separately needs no digit table.
    let byte: UInt8 = generator.next()
    hex.append(String(byte >> 4, radix: 16))
    hex.append(String(byte & 0x0F, radix: 16))
  }
  return hex
}
