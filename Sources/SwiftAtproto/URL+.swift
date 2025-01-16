//
//  URL+.swift
//  SwiftAtproto
//
//  Created by Noriaki Watanabe on 2025/01/16.
//

import Foundation

extension CharacterSet {
    private static let alpha = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"
    private static let digit = "0123456789"
    private static let hexdig = digit + "ABCDEFabcdef"
    private static let unreserved = alpha + digit + "-._~"
    static let parameterAllowed = CharacterSet(charactersIn: alpha + digit + "-._")
    static let nsidAllowed = CharacterSet(charactersIn: unreserved + "!'()*")
}

extension URL {
    func appending(percentEncodedQueryItems queryItems: [URLQueryItem]) -> URL {
        if var c = URLComponents(url: self, resolvingAgainstBaseURL: true) {
            var newItems = c.percentEncodedQueryItems ?? []
            newItems.append(contentsOf: queryItems)
            c.percentEncodedQueryItems = newItems
            if let url = c.url {
                return url
            }
        }
        return self
    }

    mutating func append(percentEncodedQueryItems queryItems: [URLQueryItem]) {
        self = appending(percentEncodedQueryItems: queryItems)
    }
}
