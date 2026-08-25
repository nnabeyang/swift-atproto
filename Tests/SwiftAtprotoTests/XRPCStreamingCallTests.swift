import Foundation
import HTTPTypes
import Testing

@testable import SwiftAtproto

@Suite("XRPC streaming calls")
struct XRPCStreamingCallTests {
  @Test("returns successful metadata before consuming the body")
  func returnsStreamingResponse() async throws {
    var headers = HTTPFields()
    headers[.contentType] = "application/vnd.ipld.car"
    let client = StreamingTestClient(
      response: .init(
        statusCode: 206,
        headers: headers,
        body: XRPCBody(Data([1, 2, 3]))))

    let response = try await client.callStreaming(
      StreamingTestQuery.self,
      input: .init())

    #expect(response.statusCode == 206)
    #expect(response.headers[.contentType] == "application/vnd.ipld.car")
    #expect(try await response.body.collect(upTo: 3) == Data([1, 2, 3]))
  }

  @Test("keeps the existing Data call compatible")
  func collectsForLegacyCall() async throws {
    let client = StreamingTestClient(
      response: .init(statusCode: 200, body: XRPCBody(Data([4, 5]))))

    let body = try await client.call(StreamingTestQuery.self, input: .init())

    #expect(body == Data([4, 5]))
  }
}

private struct StreamingTestClient: XRPCStreamingCallable {
  let streamedResponse: XRPCStreamingResponseComponents

  init(response: XRPCStreamingResponseComponents) {
    streamedResponse = response
  }

  func getProxy(nsid _: String) -> String? { nil }

  func responseStreamWithMetadata(
    _: XRPCRequestComponents
  ) async throws -> XRPCStreamingResponseComponents {
    streamedResponse
  }
}

private struct StreamingTestQuery: XRPCQuery, XRPCBinaryResponseRequest {
  static let id = "com.example.stream"
  typealias Input = StreamingTestInput
  typealias ResponseBody = Data
  typealias Error = StreamingTestError
}

private struct StreamingTestInput: XRPCQueryInput {
  struct Query: XRPCInputQuery {
    var asParameters: Parameters? { nil }
  }

  let query = Query()
}

private enum StreamingTestError: XRPCError {
  case unexpected(error: String?, message: String?)

  init(error: UnExpectedError) {
    self = .unexpected(error: error.error, message: error.message)
  }

  var error: String? {
    if case .unexpected(let error, _) = self { return error }
    return nil
  }

  var message: String? {
    if case .unexpected(_, let message) = self { return message }
    return nil
  }
}
