import Foundation

// Identifies the on-disk checkout subdirectory for a remote lexicon repository.
// `segments` is `<scheme>` + `<host[:port]>` (lowercased, default port stripped)
// followed by every non-empty path component, with a trailing `.git` stripped
// from the last one. The path depth is not fixed:
// `https://example.com/path/to/repo.git` becomes
// `["https", "example.com", "path", "to", "repo"]`, producing
// `.lexicons/checkouts/https/example.com/path/to/repo` once joined to the
// checkout root. Different schemes/ports/host casings always map to distinct
// directories so two URLs that point at different remotes never collide.
public struct RepositoryLocation: Equatable, Sendable {
  public let segments: [String]

  public init(segments: [String]) {
    self.segments = segments
  }

  public static func parse(from url: URL) throws -> RepositoryLocation {
    guard let scheme = url.scheme?.lowercased(), !scheme.isEmpty else {
      throw RepositoryLocationError.unsupportedURL(redactedDescription(of: url))
    }
    if scheme == "file" {
      // `file://` is the local-lexicon escape hatch and never produces a
      // checkout directory.
      throw RepositoryLocationError.unsupportedURL(redactedDescription(of: url))
    }
    guard let rawHost = url.host(), !rawHost.isEmpty else {
      throw RepositoryLocationError.unsupportedURL(redactedDescription(of: url))
    }
    let host = rawHost.lowercased()
    let authority: String
    if let port = url.port, port != defaultPort(for: scheme) {
      authority = "\(host):\(port)"
    } else {
      authority = host
    }
    let pathSegments = url.pathComponents.filter { $0 != "/" && !$0.isEmpty }
    guard !pathSegments.isEmpty else {
      throw RepositoryLocationError.unsupportedURL(redactedDescription(of: url))
    }
    // Reject path-traversal segments so a malicious or typo-ed URL cannot
    // escape `.lexicons/checkouts/` via `appending(components:)`.
    if pathSegments.contains(where: { $0 == "." || $0 == ".." }) {
      throw RepositoryLocationError.unsupportedURL(redactedDescription(of: url))
    }
    var result = [scheme, authority]
    result.append(contentsOf: pathSegments.dropLast())
    var repo = pathSegments.last!
    if repo.hasSuffix(".git") {
      repo = String(repo.dropLast(4))
    }
    guard !repo.isEmpty else {
      throw RepositoryLocationError.unsupportedURL(redactedDescription(of: url))
    }
    result.append(repo)
    return RepositoryLocation(segments: result)
  }

  private static func defaultPort(for scheme: String) -> Int? {
    switch scheme {
    case "https": return 443
    case "http": return 80
    case "ssh": return 22
    case "git": return 9418
    default: return nil
    }
  }

  // Strip userinfo (token:secret@) before rendering a URL into a user-visible
  // error message so credentials embedded in `.atproto.json` never leak into
  // CI logs.
  static func redactedDescription(of url: URL) -> String {
    guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
      return url.scheme.map { "\($0)://<unparseable>" } ?? "<unparseable>"
    }
    components.user = nil
    components.password = nil
    return components.string ?? url.scheme.map { "\($0)://<unparseable>" } ?? "<unparseable>"
  }
}

// The associated value is a redacted URL description (never the raw URL value),
// so equality works on plain strings instead of `URL`'s normalization-sensitive
// `==`, and userinfo cannot leak through error rendering or comparisons.
public enum RepositoryLocationError: Error, CustomStringConvertible, Equatable {
  case unsupportedURL(String)

  public var description: String {
    switch self {
    case .unsupportedURL(let location):
      return
        "Cannot derive a checkout path from lexicon location \(location). Expected a URL with at least one path component (e.g. https://<host>/<path>/<repo>(.git))."
    }
  }
}
