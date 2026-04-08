import GermConvenience

public protocol XRPCCallable: Sendable {
  func response(_ requestComponents: XRPCRequestComponents) async throws -> HTTPDataResponse
  func call<X: XRPCQuery>(_ request: X.Type, input: X.Input.Query) async throws -> X.ResponseBody
  func call<X: XRPCProcedure>(_ request: X.Type, input: X.RequestBody?) async throws -> X.ResponseBody
}
