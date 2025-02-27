import Foundation
#if os(Linux)
    import AsyncHTTPClient
    import NIOFoundationCompat
    import NIOHTTP1
#endif

public enum HTTPMethod {
    case get
    case post
}

public protocol XRPCClientProtocol: Sendable {
    var serviceEndpoint: URL { get }
    var decoder: JSONDecoder { get }
    var auth: any AuthInfo { get set }

    func tokenIsExpired(error: UnExpectedError) -> Bool
    func getAuthorization(endpoint: String) -> String?

    mutating func fetch<T: Decodable>(
        endpoint: String, contentType: String, httpMethod: HTTPMethod, params: (some Encodable)?,
        input: (some Encodable)?, retry: Bool
    ) async throws -> T
    mutating func refreshSession() async -> Bool
    mutating func signout()

    static var XRPCErrorDomain: String { get }
    static func setModuleName()
}

#if os(Linux)
    typealias URLRequest = HTTPClientRequest
    extension URLRequest {
        init(url: URL) {
            self.init(url: url.absoluteString)
        }

        mutating func addValue(_ value: String, forHTTPHeaderField field: String) {
            headers.add(name: field, value: value)
        }

        var httpBody: Data? {
            get {
                // Not Implemented
                nil
            }

            set {
                guard let newValue else { return }
                body = .bytes(newValue)
            }
        }

        var httpMethod: String? {
            get {
                method.rawValue
            }
            set {
                guard let newValue else { return }
                method = .init(rawValue: newValue)
            }
        }
    }

    extension HTTPClient {
        func executeTask(for request: URLRequest) async throws -> (Data, UInt) {
            let response = try await execute(request, timeout: .seconds(30))
            let expectedBytes = response.headers.first(name: "content-length").flatMap(Int.init) ?? 0
            var body = try await response.body.collect(upTo: expectedBytes)
            let data = body.readData(length: body.readableBytes)!
            return (data, response.status.code)
        }
    }
#else
    typealias HTTPClient = URLSession
    extension HTTPClient {
        func executeTask(for request: URLRequest) async throws -> (Data, UInt) {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                fatalError()
            }
            return (data, UInt(httpResponse.statusCode))
        }
    }
#endif

public extension XRPCClientProtocol {
    static var XRPCErrorDomain: String { "XRPCErrorDomain" }

    static func setModuleName() {
        LexiconTypesMap.shared.moduleName = _typeName(type(of: self)).split(separator: ".").first.flatMap { String($0) } ?? ""
    }

    private static func encode(_ string: String, component: XRPCComponent) -> String {
        switch component {
        case .nsid:
            string.addingPercentEncoding(withAllowedCharacters: .nsidAllowed) ?? string
        case .parameter:
            string.addingPercentEncoding(withAllowedCharacters: .parameterAllowed) ?? string
        }
    }

    mutating func fetch<T: Decodable>(
        endpoint nsid: String, contentType: String, httpMethod: HTTPMethod, params: (some Encodable)?, input: (some Encodable)?, retry: Bool
    ) async throws -> T {
        var url = serviceEndpoint.appending(path: Self.encode(nsid, component: .nsid))
        if httpMethod == .get, let params = params?.dictionary {
            url.append(percentEncodedQueryItems: Self.makeParameters(params: params))
        }

        var request = URLRequest(url: url)
        request.addValue("application/json", forHTTPHeaderField: "Accept")
        if let authorization = getAuthorization(endpoint: nsid) {
            request.addValue("Bearer \(authorization)", forHTTPHeaderField: "Authorization")
        }
        switch httpMethod {
        case .get:
            request.httpMethod = "GET"
        case .post:
            request.httpMethod = "POST"
            request.addValue(contentType, forHTTPHeaderField: "Content-Type")
            if let input {
                let encoder = JSONEncoder()
                encoder.dataEncodingStrategy = Self.dataEncodingStrategy
                encoder.outputFormatting = [.withoutEscapingSlashes]
                let body: Data = switch input {
                case let data as Data:
                    data
                default:
                    try encoder.encode(input)
                }
                request.httpBody = body
                request.addValue("\(body.count)", forHTTPHeaderField: "Content-Length")
            }
        }

        let (data, statusCode) = try await HTTPClient.shared.executeTask(for: request)

        guard 200 ... 299 ~= statusCode else {
            if let error = try? decoder.decode(UnExpectedError.self, from: data) {
                if tokenIsExpired(error: error), retry, await refreshSession() {
                    return try await fetch(
                        endpoint: Self.encode(nsid, component: .nsid), contentType: contentType, httpMethod: httpMethod,
                        params: params, input: input, retry: false
                    )
                }
                throw error
            } else {
                let message = String(decoding: data, as: UTF8.self)
                throw NSError(domain: Self.XRPCErrorDomain, code: 0, userInfo: [NSLocalizedDescriptionKey: "Server error: \(message)(\(statusCode))"])
            }
        }

        if T.self == Bool.self {
            return true as! T
        }
        if T.self == Data.self {
            return data as! T
        }
        return try decoder.decode(T.self, from: data)
    }

    static func makeParameters(params: [String: Any]) -> [URLQueryItem] {
        var items = [URLQueryItem]()
        for param in params {
            if let seq = param.value as? [String] {
                items.append(contentsOf: seq.map { URLQueryItem(name: encode(param.key, component: .parameter), value: encode($0, component: .parameter)) })
            } else {
                items.append(URLQueryItem(name: encode(param.key, component: .parameter), value: encode("\(param.value)", component: .parameter)))
            }
        }
        return items
    }

    internal static var dataEncodingStrategy: JSONEncoder.DataEncodingStrategy {
        .custom { data, encoder in
            do {
                if !data.isEmpty, data[0] == 0 {
                    try LexLink.dataEncodingStrategy(data: data, encoder: encoder)
                    return
                }
            } catch {}
            if let string = String(data: data, encoding: .utf8) {
                try string.encode(to: encoder)
            } else {
                try data.base64Encoded().encode(to: encoder)
            }
        }
    }
}

public protocol XRPCError: Error, LocalizedError, Decodable, Sendable {
    var error: String? { get }
    var message: String? { get }
}

public extension XRPCError {
    var errorDescription: String? {
        message
    }
}

public final class UnExpectedError: XRPCError {
    public let error: String?
    public let message: String?
    public init(error: String?, message: String?) {
        self.error = error
        self.message = message
    }
}

public struct UnknownRecord: Identifiable, Codable, Sendable {
    public let type: String
    enum CodingKeys: String, CodingKey {
        case type = "$type"
    }

    public var id: String { UUID().uuidString }

    public init(type: String) {
        self.type = type
    }
}

enum XRPCComponent {
    case nsid
    case parameter
}
