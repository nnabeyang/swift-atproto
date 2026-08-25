import Foundation
import Testing

@testable import SwiftAtproto

@Suite("XRPC streaming body")
struct XRPCBodyTests {
  @Test("collects transport chunks without changing their order")
  func collectsChunks() async throws {
    let chunks = AsyncStream<ArraySlice<UInt8>> { continuation in
      continuation.yield([1, 2])
      continuation.yield([3, 4])
      continuation.finish()
    }
    let body = XRPCBody(chunks, length: .known(4))

    #expect(try await body.collect(upTo: 4) == Data([1, 2, 3, 4]))
  }

  @Test("rejects a known body larger than the collection limit")
  func enforcesKnownLengthLimit() async {
    let body = XRPCBody(Data([1, 2, 3]))

    await #expect(throws: XRPCBodyError.tooManyBytes(limit: 2)) {
      _ = try await body.collect(upTo: 2)
    }
  }

  @Test("allows only one iterator")
  func isSinglePass() async throws {
    let body = XRPCBody(Data([1]))
    var first = body.makeAsyncIterator()
    #expect(try await first.next() == [1])
    var second = body.makeAsyncIterator()

    await #expect(throws: XRPCBodyError.alreadyConsumed) {
      _ = try await second.next()
    }
  }
}
