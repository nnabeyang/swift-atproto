// Internal base32-sortable encoder/decoder for fixed 13-character TID encoding per the AT
// Protocol TID spec (https://atproto.com/specs/tid). The alphabet
// `234567abcdefghijklmnopqrstuvwxyz` preserves lexicographic order for chronological sort.
//
// Encoding packs a 64-bit value MSB-first into 13 base32 characters (5 bit × 13 = 65 bit; the
// top bit is always zero per spec, so it is discarded). Decoding reverses the same mapping.

private let base32SortableAlphabet: [Character] = Array("234567abcdefghijklmnopqrstuvwxyz")
private let base32SortableIndex: [Character: UInt64] = {
  var dict: [Character: UInt64] = [:]
  for (i, c) in base32SortableAlphabet.enumerated() {
    dict[c] = UInt64(i)
  }
  return dict
}()

// Encode the bottom 65 bits of `value` as a 13-char base32-sortable string. The leading char
// reflects bits 60..64; the trailing char reflects bits 0..4.
func encodeBase32Sortable(value: UInt64) -> String {
  var chars: [Character] = []
  chars.reserveCapacity(13)
  for i in 0..<13 {
    let shift = 5 * (12 - i)
    let bits = (value >> shift) & 0x1F
    chars.append(base32SortableAlphabet[Int(bits)])
  }
  return String(chars)
}

// Decode a 13-char base32-sortable string back into its 65-bit value. Returns nil for any
// length other than 13 or for any character outside the alphabet.
func decodeBase32Sortable(_ s: some StringProtocol) -> UInt64? {
  guard s.count == 13 else { return nil }
  var value: UInt64 = 0
  for c in s {
    guard let bits = base32SortableIndex[c] else { return nil }
    value = (value << 5) | bits
  }
  return value
}
