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

  // MARK: deterministic (dependency-injected) generator

  @Test func deterministicGeneratorRoundTripsInputs() {
    let now: UInt64 = 1_700_000_000_000_000
    let clockId: UInt16 = 42
    let tid = TID.next(prev: nil, now: now, clockId: clockId)
    #expect(tid.timestamp == now)
    #expect(tid.clockId == clockId)
  }

  @Test func deterministicGeneratorBumpsWhenNowEqualsPrev() {
    let prev = TID.next(prev: nil, now: 1_000_000, clockId: 0)
    let tid = TID.next(prev: prev, now: 1_000_000, clockId: 0)
    #expect(tid.timestamp == 1_000_001)
  }

  @Test func deterministicGeneratorBumpsWhenNowBeforePrev() {
    let prev = TID.next(prev: nil, now: 2_000_000, clockId: 0)
    let tid = TID.next(prev: prev, now: 1_500_000, clockId: 0)
    #expect(tid.timestamp == 2_000_001)
  }

  @Test func deterministicGeneratorDoesNotBumpWhenNowAfterPrev() {
    let prev = TID.next(prev: nil, now: 1_000_000, clockId: 0)
    let tid = TID.next(prev: prev, now: 2_000_000, clockId: 0)
    #expect(tid.timestamp == 2_000_000)
  }

  @Test func deterministicGeneratorAcceptsUpperTenBitClockId() {
    let tid = TID.next(prev: nil, now: 1_000_000, clockId: 1023)
    #expect(tid.clockId == 1023)
  }

  // MARK: monotonicity

  @Test func consecutiveNextCallsAreMonotonicallyIncreasing() {
    var prev: TID? = nil
    var allRaw: [String] = []
    for _ in 0..<1000 {
      let tid = TID.next(prev: prev)
      if let prev {
        #expect(tid.timestamp > prev.timestamp)
      }
      allRaw.append(tid.rawValue)
      prev = tid
    }
    // All-unique rawValues falls out of strict monotonicity, but assert it explicitly to
    // catch any accidental clockId collision in same-microsecond cases.
    #expect(Set(allRaw).count == 1000)
  }

  @Test func concurrentNextCallsProduceUniqueTIDs() async {
    let ids = await withTaskGroup(of: TID.self, returning: [TID].self) { group in
      for _ in 0..<1000 {
        group.addTask { TID.next() }
      }
      var collected: [TID] = []
      for await tid in group {
        collected.append(tid)
      }
      return collected
    }
    #expect(ids.count == 1000)
    #expect(Set(ids.map(\.rawValue)).count == 1000)
  }
}
