import Foundation

/// A client that talks to one AT Protocol service.
///
/// Refines the callable infrastructure with the endpoint and session hooks a
/// transport needs. Implementing `response(_:)` is still the only
/// transport-specific work; see <doc:MakingXRPCCalls>.
public protocol ATPClientProtocol: _XRPCCallable {
  /// The service base URL that `/xrpc/<nsid>` is appended to.
  var serviceEndpoint: URL { get }
  /// The decoder used for response payloads.
  var decoder: JSONDecoder { get }

  /// Whether this error means the access token needs refreshing, so the call
  /// can be retried after ``refreshSession()``.
  func tokenIsExpired(error: some XRPCError) -> Bool
  /// The `Authorization` header value to send for this method, or `nil` for an
  /// unauthenticated call.
  func getAuthorization(endpoint: String) -> String?

  /// Refreshes the session, returning whether it succeeded.
  func refreshSession() async -> Bool
}

/// A client backed by mutable session credentials.
///
/// This protocol is infrastructure shared with generated code and with the
/// deprecated `@XRPCClient` macro. Prefer the `XRPCClientProtocol` emitted by
/// code generation, which also carries the XRPC method requirements.
public protocol _XRPCClientProtocol: ATPClientProtocol {
  /// The credentials this client sends.
  var auth: any XRPCAuth { get set }

  /// Discards the current session.
  func signout()
}

extension ATPClientProtocol {
  public func getProxy(nsid _: String) -> String? { nil }
}

extension ATPClientProtocol where Self: XRPCSubscriptionCallable {
  public func prepareSubscriptionRequest(
    _ components: XRPCSubscriptionRequestComponents
  ) async throws -> XRPCWebSocketRequest {
    var urlComponents = URLComponents(
      url: serviceEndpoint.appending(path: "xrpc/\(components.nsId)"),
      resolvingAgainstBaseURL: false)
    switch urlComponents?.scheme {
    case "https": urlComponents?.scheme = "wss"
    case "http": urlComponents?.scheme = "ws"
    default: break
    }
    urlComponents?.percentEncodedQueryItems = components.queryItems
    guard let url = urlComponents?.url else {
      throw URLError(.badURL)
    }
    var headers = components.headers
    if let authorization = getAuthorization(endpoint: components.nsId) {
      headers[.authorization] = authorization
    }
    return XRPCWebSocketRequest(url: url, headers: headers)
  }
}

/// An error payload declared by a Lexicon method.
///
/// One conforming type is generated per method. A failure the Lexicon does not
/// describe arrives as ``UnExpectedError`` and is converted through
/// ``init(error:)``.
public protocol XRPCError: Error, LocalizedError, Decodable, Sendable {
  /// The machine-readable error name returned by the service.
  var error: String? { get }
  /// The human-readable message returned by the service.
  var message: String? { get }
  /// Wraps a failure that the method's Lexicon does not describe.
  init(error: UnExpectedError)
}

extension XRPCError {
  public var errorDescription: String? {
    message
  }
}

/// A failure that no Lexicon error case describes, such as a transport error
/// or an unrecognized status.
public final class UnExpectedError: XRPCError {
  public let error: String?
  public let message: String?
  public init(error: String?, message: String?) {
    self.error = error
    self.message = message
  }

  public init(error: UnExpectedError) {
    self.error = error.error
    self.message = error.message
  }
}

/// A record whose `$type` this module was not generated against.
///
/// The unrecognized fields are kept in `_unknownValues` so the record
/// re-encodes exactly as it arrived. See <doc:DecodingLexiconRecords>.
public struct UnknownRecord: Identifiable, ATProtoRecord {
  public static let nsId = "unknown"
  public let type: String
  public var _unknownValues: [String: AnyCodable]

  enum CodingKeys: String, CodingKey {
    case type = "$type"
  }

  public var id: String { UUID().uuidString }

  public init(type: String) {
    self.type = type
    _unknownValues = [:]
  }

  public init(from decoder: any Decoder) throws {
    let keyedContainer = try decoder.container(keyedBy: CodingKeys.self)
    type = try keyedContainer.decode(String.self, forKey: .type)
    let unknownContainer = try decoder.container(keyedBy: AnyCodingKeys.self)
    var _unknownValues = [String: AnyCodable]()
    for key in unknownContainer.allKeys {
      guard CodingKeys(rawValue: key.stringValue) == nil else {
        continue
      }
      _unknownValues[key.stringValue] = try unknownContainer.decode(AnyCodable.self, forKey: key)
    }
    self._unknownValues = _unknownValues
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(type, forKey: .type)
    try _unknownValues.encode(to: encoder)
  }
}

enum XRPCComponent {
  case nsid
  case parameter
}
