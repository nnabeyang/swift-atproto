import Foundation
import Testing

@testable import SwiftAtproto

struct RequiredRpcLxmTests {
  @Test func requiredRpcLxmReturnsIdForQuery() {
    #expect(StubQuery.requiredRpcLxm() == "com.example.stub.query")
  }

  @Test func requiredRpcLxmReturnsIdForProcedure() {
    #expect(StubProcedure.requiredRpcLxm() == "com.example.stub.procedure")
  }
}

struct StubQueryInput: XRPCQueryInput {
  struct Query: XRPCInputQuery {
    var asParameters: Parameters? { nil }
  }
  var query: Query { Query() }
}

enum StubQuery: XRPCQuery {
  static let id = "com.example.stub.query"
  typealias Input = StubQueryInput
  typealias ResponseBody = EmptyResponse
  typealias Error = UnExpectedError
}

enum StubProcedure: XRPCProcedure {
  static let id = "com.example.stub.procedure"
  static let contentType = "application/json"
  typealias RequestBody = EmptyResponse
  typealias ResponseBody = EmptyResponse
  typealias Error = UnExpectedError
}
