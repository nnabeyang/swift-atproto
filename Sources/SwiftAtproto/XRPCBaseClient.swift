import Foundation

public protocol XRPCClientProtocol {
    func fetch<T: Decodable>(
        endpoint: String, contentType: String, httpMethod: XRPCBaseClient.HTTPMethod, params: (some Encodable)?,
        input: (some Encodable)?, retry: Bool
    ) async throws -> T
    func refreshSession() async -> Bool

    func getAuthorization(endpoint: String) -> String
}

open class XRPCBaseClient: XRPCClientProtocol {
    private let host: URL
    private let decoder: JSONDecoder
    public var auth = AuthInfo()
    public enum HTTPMethod {
        case get
        case post
    }

    public init(host: URL) {
        self.host = host.appending(path: "xrpc")
        decoder = JSONDecoder()
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

    public func fetch<T: Decodable>(
        endpoint: String, contentType: String, httpMethod: HTTPMethod, params: (some Encodable)?, input: (some Encodable)?, retry: Bool
    ) async throws -> T {
        let authorization = getAuthorization(endpoint: endpoint)
        var url = host.appending(path: endpoint)
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
            throw NSError(domain: "", code: 0, userInfo: [NSLocalizedDescriptionKey: "Server error: 0"])
        }

        guard 200 ... 299 ~= httpResponse.statusCode else {
            do {
                let xrpcerror = try decoder.decode(XRPCError.self, from: data)
                if retry {
                    if xrpcerror.error == "ExpiredToken" {
                        if await refreshSession() {
                            return try await fetch(
                                endpoint: endpoint, contentType: contentType, httpMethod: httpMethod,
                                params: params, input: input, retry: false
                            )
                        }
                    }
                }
                throw xrpcerror
            } catch {
                if error is XRPCError {
                    throw error
                }
                throw NSError(domain: "", code: 0, userInfo: [NSLocalizedDescriptionKey: "Server error: \(httpResponse.statusCode)"])
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

    open func refreshSession() async -> Bool {
        false
    }

    open func getAuthorization(endpoint _: String) -> String {
        _abstract()
    }
}

struct XRPCError: Error, LocalizedError, Decodable {
    let error: String?
    let message: String?
    var errorDescription: String? {
        message
    }
}
