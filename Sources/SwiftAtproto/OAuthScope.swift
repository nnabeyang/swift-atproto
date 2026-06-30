import Foundation

public enum OAuthScope {
  public static let atproto = "atproto"
}

public enum OAuthScopeError: Error, Hashable, Sendable {
  case invalidSyntax(String)
  case invalidResource(String)
  case duplicateKey(String)
  case missingRequired(String)
  case forbiddenCombination(String)
  case permissionAudMismatch(String)
  case nsidOutsideAuthority(parent: String, other: String)
  case unsupportedResource(String)
}

public struct RpcScope: CustomStringConvertible, Hashable, Sendable {
  public let aud: String
  public let lxm: [String]

  public init(aud: String, lxm: [String]) throws {
    guard !lxm.isEmpty else {
      throw OAuthScopeError.missingRequired("lxm")
    }
    let normalized = Self.normalize(lxm: lxm)
    if aud == "*", normalized.contains("*") {
      throw OAuthScopeError.forbiddenCombination("rpc:* with aud:*")
    }
    self.aud = aud
    self.lxm = normalized
  }

  public init(string: String) throws {
    let syntax = OAuthScopeSyntax.parse(string)
    guard syntax.prefix == "rpc" else {
      throw OAuthScopeError.invalidResource(syntax.prefix)
    }
    var lxms: [String] = []
    var aud: String? = nil
    var sawLxmInQuery = false
    if let positional = syntax.positional {
      guard !positional.isEmpty else {
        throw OAuthScopeError.invalidSyntax("empty positional in rpc scope")
      }
      lxms.append(positional)
    }
    for param in syntax.params {
      switch param.key {
      case "lxm":
        sawLxmInQuery = true
        guard !param.value.isEmpty else {
          throw OAuthScopeError.invalidSyntax("empty lxm value in rpc scope")
        }
        lxms.append(param.value)
      case "aud":
        if aud != nil {
          throw OAuthScopeError.duplicateKey("aud")
        }
        aud = param.value
      default:
        throw OAuthScopeError.invalidSyntax("unknown key '\(param.key)' in rpc scope")
      }
    }
    if syntax.positional != nil, sawLxmInQuery {
      throw OAuthScopeError.invalidSyntax("rpc scope has both positional and lxm query")
    }
    guard let audValue = aud, !audValue.isEmpty else {
      throw OAuthScopeError.missingRequired("aud")
    }
    try self.init(aud: audValue, lxm: lxms)
  }

  public var description: String {
    var params: [OAuthScopeQueryParam] = []
    var positional: String? = nil
    if lxm.count == 1 {
      positional = lxm[0]
    } else {
      for value in lxm {
        params.append(OAuthScopeQueryParam(key: "lxm", value: value))
      }
    }
    params.append(OAuthScopeQueryParam(key: "aud", value: aud))
    return OAuthScopeSyntax(prefix: "rpc", positional: positional, params: params).description
  }

  private static func normalize(lxm: [String]) -> [String] {
    if lxm.count > 1, lxm.contains("*") {
      return ["*"]
    }
    return Array(Set(lxm)).sorted()
  }
}
