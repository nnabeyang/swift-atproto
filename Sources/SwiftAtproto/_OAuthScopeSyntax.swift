import Foundation

struct OAuthScopeQueryParam: Equatable, Hashable, Sendable {
  let key: String
  let value: String
}

struct OAuthScopeSyntax: CustomStringConvertible, Equatable, Hashable, Sendable {
  let prefix: String
  let positional: String?
  let params: [OAuthScopeQueryParam]

  init(prefix: String, positional: String? = nil, params: [OAuthScopeQueryParam] = []) {
    self.prefix = prefix
    self.positional = positional
    self.params = params
  }

  static func parse(_ scope: String) -> OAuthScopeSyntax {
    let colonIdx = scope.firstIndex(of: ":")
    let queryIdx = scope.firstIndex(of: "?")
    let prefixEnd: String.Index? = minIndex(colonIdx, queryIdx)
    guard let prefixEnd else {
      return OAuthScopeSyntax(prefix: scope)
    }
    let prefix = String(scope[..<prefixEnd])

    let positional: String?
    if let colonIdx, colonIdx < (queryIdx ?? scope.endIndex) {
      let positionalEnd = queryIdx ?? scope.endIndex
      let raw = String(scope[scope.index(after: colonIdx)..<positionalEnd])
      positional = decodePercent(raw)
    } else {
      positional = nil
    }

    var params: [OAuthScopeQueryParam] = []
    if let queryIdx, scope.index(after: queryIdx) < scope.endIndex {
      let query = scope[scope.index(after: queryIdx)...]
      for pair in query.split(separator: "&", omittingEmptySubsequences: true) {
        let parts = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
        let key = decodePercent(String(parts[0]))
        let value = parts.count == 2 ? decodePercent(String(parts[1])) : ""
        params.append(OAuthScopeQueryParam(key: key, value: value))
      }
    }
    return OAuthScopeSyntax(prefix: prefix, positional: positional, params: params)
  }

  var description: String {
    var result = prefix
    if let positional {
      result += ":" + normalizeAllowedChars(encodeComponent(positional))
    }
    if !params.isEmpty {
      let joined = params.map { encodeComponent($0.key) + "=" + encodeComponent($0.value) }.joined(separator: "&")
      result += "?" + normalizeAllowedChars(joined)
    }
    return result
  }
}

private func minIndex(_ a: String.Index?, _ b: String.Index?) -> String.Index? {
  switch (a, b) {
  case (nil, nil): nil
  case (let x?, nil): x
  case (nil, let y?): y
  case (let x?, let y?): min(x, y)
  }
}

private let unreservedScopeCharacters: CharacterSet = {
  var set = CharacterSet.alphanumerics
  set.insert(charactersIn: "-_.!~*'()")
  return set
}()

private func encodeComponent(_ value: String) -> String {
  value.addingPercentEncoding(withAllowedCharacters: unreservedScopeCharacters) ?? value
}

private func decodePercent(_ value: String) -> String {
  value.removingPercentEncoding ?? value
}

private let allowedNormalizableEncoded: [String: String] = [
  "%3A": ":",
  "%2F": "/",
  "%2B": "+",
  "%2C": ",",
  "%40": "@",
  "%25": "%",
]

private func normalizeAllowedChars(_ value: String) -> String {
  guard value.contains("%") else { return value }
  var result = ""
  result.reserveCapacity(value.count)
  let chars = Array(value)
  var i = 0
  while i < chars.count {
    if chars[i] == "%", i + 2 < chars.count {
      let encoded = String(chars[i...i + 2]).uppercased()
      if let decoded = allowedNormalizableEncoded[encoded] {
        result.append(decoded)
        i += 3
        continue
      }
    }
    result.append(chars[i])
    i += 1
  }
  return result
}
