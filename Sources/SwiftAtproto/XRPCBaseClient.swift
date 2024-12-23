import Foundation

public enum HTTPMethod {
    case get
    case post
}

public protocol XRPCClientProtocol: Sendable {
    var serviceEndpoint: URL { get }
    var decoder: JSONDecoder { get }
    var auth: AuthInfo { get set }

    func tokenIsExpired(error: UnExpectedError) -> Bool
    func getAuthorization(endpoint: String) -> String

    mutating func fetch<T: Decodable>(
        endpoint: String, contentType: String, httpMethod: HTTPMethod, params: (some Encodable)?,
        input: (some Encodable)?, retry: Bool
    ) async throws -> T
    mutating func refreshSession() async -> Bool
    mutating func signout()

    static var XRPCErrorDomain: String { get }
    static func setModuleName()
}

public extension XRPCClientProtocol {
    static var XRPCErrorDomain: String { "XRPCErrorDomain" }

    static func setModuleName() {
        LexiconTypesMap.shared.moduleName = _typeName(type(of: self)).split(separator: ".").first.flatMap { String($0) } ?? ""
    }

    mutating func fetch<T: Decodable>(
        endpoint: String, contentType: String, httpMethod: HTTPMethod, params: (some Encodable)?, input: (some Encodable)?, retry: Bool
    ) async throws -> T {
        let authorization = getAuthorization(endpoint: endpoint)
        var url = serviceEndpoint.appending(path: endpoint)
        if httpMethod == .get, let params = params?.dictionary {
            url.append(queryItems: Self.makeParameters(params: params))
        }

        var request = URLRequest(url: url)
        request.addValue("application/json", forHTTPHeaderField: "Accept")
        request.addValue("Bearer \(authorization)", forHTTPHeaderField: "Authorization")
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
                switch input {
                case let data as Data:
                    request.httpBody = data
                default:
                    request.httpBody = try? encoder.encode(input)
                }
                request.addValue("\(request.httpBody?.count ?? 0)", forHTTPHeaderField: "Content-Length")
            }
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: Self.XRPCErrorDomain, code: 0, userInfo: [NSLocalizedDescriptionKey: "Server error: 0"])
        }

        guard 200 ... 299 ~= httpResponse.statusCode else {
            if let error = try? decoder.decode(UnExpectedError.self, from: data) {
                if tokenIsExpired(error: error), retry, await refreshSession() {
                    return try await fetch(
                        endpoint: endpoint, contentType: contentType, httpMethod: httpMethod,
                        params: params, input: input, retry: false
                    )
                }
                throw error
            } else {
                let message = String(decoding: data, as: UTF8.self)
                throw NSError(domain: Self.XRPCErrorDomain, code: 0, userInfo: [NSLocalizedDescriptionKey: "Server error: \(message)(\(httpResponse.statusCode))"])
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
                items.append(contentsOf: seq.map { URLQueryItem(name: param.key, value: $0) })
            } else {
                items.append(URLQueryItem(name: param.key, value: "\(param.value)"))
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
