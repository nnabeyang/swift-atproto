//
//  URL+.swift
//  SwiftAtproto
//
//  Created by Noriaki Watanabe on 2025/01/16.
//

import Foundation

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
