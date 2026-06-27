import Foundation
import Testing

@testable import SwiftAtproto

// Behavior tests for `TID.next()` (the public default-clock generator) and the internal
// dependency-injected variant. Parser/accessor concerns live in `TIDInteropTests`.
struct TIDGeneratorTests {
  @Test func nextProducesValidTID() {
    let tid = TID.next()
    #expect(TID.isValid(tid.rawValue))
    #expect(tid.rawValue.utf8.count == 13)
  }

  @Test func nextProducesValidTIDsRepeatedly() {
    for _ in 0..<100 {
      let tid = TID.next()
      #expect(TID.isValid(tid.rawValue))
    }
  }

  @Test func nextTimestampIsApproximatelyNow() {
    let nowMicros = UInt64(Date().timeIntervalSince1970 * 1_000_000)
    let tid = TID.next()
    // The generator quantizes to millisecond resolution then advances a sub-ms counter, so
    // the absolute diff from "now" can be a few ms — accept up to ±1 second to cover slow CI.
    let diff = tid.timestamp > nowMicros ? tid.timestamp - nowMicros : nowMicros - tid.timestamp
    #expect(diff < 1_000_000)
  }

  @Test func nextClockIdIsWithinTenBitRange() {
    let tid = TID.next()
    #expect(tid.clockId < 1024)
  }
}
