import Foundation

// Type for the lexicon `tid` string format: AT Protocol Timestamp Identifier per the AT Protocol
// TID spec (https://atproto.com/specs/tid).
//
// Wire-shape validation only: a 13-character base32-sortable token. The first character is from
// `[234567abcdefghij]` (the high bit of the encoded timestamp is always zero in the foreseeable
// future, restricting the leading character to the lower 16 of the 32-char alphabet). The
// remaining 12 characters are from the full base32-sortable alphabet
// `[234567abcdefghijklmnopqrstuvwxyz]`.
public struct TID: LexiconStringFormat {
  // The original wire string, kept verbatim.
  public let rawValue: String

  public init(string: String) throws {
    guard TID.isValid(string) else {
      throw LexiconStringFormatError.invalid(format: "tid", value: string)
    }
    rawValue = string
  }
}

extension TID {
  // Strict per the grammar above. Accepts `String` and `Substring`.
  static func isValid(_ s: some StringProtocol) -> Bool {
    let u = Array(s.utf8)
    guard u.count == 13 else { return false }
    guard tidFirstChars.contains(u[0]) else { return false }
    for i in 1..<13 where !tidRestChars.contains(u[i]) { return false }
    return true
  }

  // Microsecond timestamp since the UNIX epoch. The top 53 bits of the 64-bit encoded value
  // per the TID spec. Returns 0 if `rawValue` cannot be decoded (unreachable for instances
  // produced by `init(string:)`, since the parser guarantees a valid base32-sortable form).
  public var timestamp: UInt64 {
    (decodeBase32Sortable(rawValue) ?? 0) >> 10
  }

  // 10-bit clock identifier (0...1023) per the TID spec. Returns 0 on a decode failure
  // (unreachable in practice — see `timestamp`).
  public var clockId: UInt16 {
    UInt16((decodeBase32Sortable(rawValue) ?? 0) & 0x3FF)
  }

  // Generate a new TID with a monotonic guarantee. Same-millisecond calls receive an
  // incrementing per-millisecond counter so consecutive TIDs never collide; clock skew
  // (system clock going backward) is absorbed by taking `max(now, lastTimestamp)`. If `prev`
  // is supplied and the freshly generated TID is not newer, the timestamp is bumped to
  // `prev.timestamp + 1` for additional safety across generator instances.
  //
  // Wire-shape correctness is guaranteed by construction: the encoded base32-sortable form is
  // always 13 characters from the allowed alphabet, so the validator inside `init(string:)`
  // never throws here.
  public static func next(prev: TID? = nil) -> TID {
    let nowMs = UInt64(Date().timeIntervalSince1970 * 1_000)
    let micros = tidClockState.advanceTimestamp(nowMs: nowMs)
    return TID.next(prev: prev, now: micros, clockId: tidClockState.defaultClockId)
  }

  // Deterministic generator for tests. Bypasses the global clock + counter and uses caller-
  // supplied `now` (microseconds since epoch) and `clockId` (0...1023). Still honors the
  // `prev` bump rule. Caller is responsible for keeping `now` within the spec-defined 53-bit
  // microsecond range — values exceeding the range may lose top bits when packed into the
  // 64-bit encoded form.
  static func next(prev: TID?, now: UInt64, clockId: UInt16) -> TID {
    var timestamp = now
    if let prev, timestamp <= prev.timestamp {
      timestamp = prev.timestamp &+ 1
    }
    let value = (timestamp << 10) | UInt64(clockId & 0x3FF)
    let raw = encodeBase32Sortable(value: value)
    return try! TID(string: raw)
  }
}

private final class TIDClockState: @unchecked Sendable {
  private let lock = NSLock()
  private var lastTimestamp: UInt64 = 0  // milliseconds
  private var timestampCount: UInt32 = 0
  // Spec-compliant 10-bit clockId range (0...1023). bluesky-social TypeScript narrowed this
  // to 5 bits (0...31) when adopting a microsecond-counter design
  // (https://github.com/bluesky-social/atproto/commit/5b0f826) and notes the collision
  // tradeoff explicitly; we keep the full 10 bits per the AT Protocol TID spec for stronger
  // collision resistance.
  let defaultClockId: UInt16 = UInt16.random(in: 0..<1024)

  func advanceTimestamp(nowMs: UInt64) -> UInt64 {
    lock.lock()
    defer { lock.unlock() }
    let timeMs = max(nowMs, lastTimestamp)
    if timeMs == lastTimestamp {
      // `&+= 1` wraps after 2^32 same-ms calls; physically unreachable (would require ~4
      // billion calls within a single millisecond) so the accepted limitation is left as-is.
      timestampCount &+= 1
    } else {
      timestampCount = 0
    }
    lastTimestamp = timeMs
    return timeMs * 1_000 + UInt64(timestampCount)
  }
}

private let tidClockState = TIDClockState()

// `[234567abcdefghij]` — first character of a TID (high bit of the timestamp is zero).
private let tidFirstChars: Set<UInt8> = Set("234567abcdefghij".utf8)
// `[234567abcdefghijklmnopqrstuvwxyz]` — full base32-sortable alphabet for subsequent chars.
private let tidRestChars: Set<UInt8> = Set("234567abcdefghijklmnopqrstuvwxyz".utf8)
