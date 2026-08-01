import Foundation
import Testing

@testable import SwiftAtproto

/// Mirrors the shape the generator emits for a query whose Lexicon puts
/// `minimum` / `maximum` on a parameter: a validating `make(...)` factory next
/// to the plain memberwise initializer.
private struct ConstrainedQueryInput: XRPCQueryInput {
  struct Query: XRPCInputQuery {
    var limit: Int?

    init(limit: Int? = nil) {
      self.limit = limit
    }

    static func make(limit: Int? = nil) throws -> Self {
      if let limit {
        guard limit >= 1 else {
          throw LexiconConstraintError.integerBelowMinimum("limit", minimum: 1)
        }
        guard limit <= 100 else {
          throw LexiconConstraintError.integerAboveMaximum("limit", maximum: 100)
        }
      }
      return Self.init(limit: limit)
    }

    var asParameters: Parameters? { ["limit": .integer(limit)] }
  }

  var query: Query
}

private enum ConstrainedQuery: XRPCQuery {
  static let id = "com.example.constrained.query"
  typealias Input = ConstrainedQueryInput
  typealias ResponseBody = EmptyResponse
  typealias Error = UnExpectedError
}

private final class ResponseCounter: @unchecked Sendable {
  var callCount = 0
}

private struct CountingClient: @unchecked Sendable, _XRPCCallable {
  let counter: ResponseCounter

  func getProxy(nsid _: String) -> String? { nil }

  func response(_: XRPCRequestComponents) async throws -> Data {
    counter.callCount += 1
    return Data("{}".utf8)
  }

  /// The body the generator emits for `ConstrainedQuery`.
  func constrainedQuery(limit: Int? = nil) async throws -> ConstrainedQuery.ResponseBody {
    try await call(ConstrainedQuery.self, input: try ConstrainedQueryInput.Query.make(limit: limit))
  }
}

struct XRPCQueryConstraintTests {
  @Test func inRangeLimitReachesTheNetwork() async throws {
    let counter = ResponseCounter()
    let client = CountingClient(counter: counter)

    _ = try await client.constrainedQuery(limit: 100)

    #expect(counter.callCount == 1)
  }

  /// Input construction happens outside `call(_:input:)`, so the constraint
  /// failure surfaces as a `LexiconConstraintError` rather than being funneled
  /// through the endpoint's `XRPCError` mapping, and no request is sent.
  @Test func limitAboveMaximumThrowsBeforeSendingTheRequest() async throws {
    let counter = ResponseCounter()
    let client = CountingClient(counter: counter)

    let error = await #expect(throws: LexiconConstraintError.self) {
      _ = try await client.constrainedQuery(limit: 101)
    }
    guard case .integerAboveMaximum(let field, let maximum) = error else {
      Issue.record("expected integerAboveMaximum, got \(String(describing: error))")
      return
    }
    #expect(field == "limit")
    #expect(maximum == 100)
    #expect(counter.callCount == 0)
  }

  @Test func limitBelowMinimumThrowsBeforeSendingTheRequest() async throws {
    let counter = ResponseCounter()
    let client = CountingClient(counter: counter)

    let error = await #expect(throws: LexiconConstraintError.self) {
      _ = try await client.constrainedQuery(limit: 0)
    }
    guard case .integerBelowMinimum(let field, let minimum) = error else {
      Issue.record("expected integerBelowMinimum, got \(String(describing: error))")
      return
    }
    #expect(field == "limit")
    #expect(minimum == 1)
    #expect(counter.callCount == 0)
  }
}
