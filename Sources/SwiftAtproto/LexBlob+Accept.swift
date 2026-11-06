import Foundation

extension LexBlob {
  /// Whether a blob of `mimeType` is one that a Lexicon's `accept` list allows.
  ///
  /// Use it to check a file before uploading it, with the list from the
  /// generated `Constraints` of the field it is for; the generated
  /// `validateConstraints()` and strict decoding check a ``LexBlob`` the same
  /// way:
  ///
  /// ```swift
  /// guard LexBlob.isAccepted(
  ///   mimeType: "video/mp4", by: App.Bsky.EmbedVideo.Constraints.videoAccept)
  /// else { throw UnsupportedVideo() }
  /// ```
  ///
  /// The Lexicon specification (https://atproto.com/specs/lexicon, `blob`)
  /// says that each entry "may end in `*` as a glob pattern (eg, `image/*`)",
  /// that "`*/*`" accepts any MIME type, and that "partial globs (`text/ht*`)
  /// or stand-alone wildcard (`*`) are not supported", so those match only a
  /// MIME type spelled exactly like them. It doesn't cover case or parameters;
  /// here the type and subtype compare without regard to case and parameters
  /// after `;` are ignored, as MIME types do (RFC 2045, RFC 6838).
  ///
  /// - Parameters:
  ///   - mimeType: The MIME type of the blob, such as `image/png`.
  ///   - accept: The `accept` list of the field. An empty list, which the
  ///     specification leaves undefined, accepts any MIME type, like an
  ///     absent one.
  /// - Returns: `true` when an entry of `accept` matches `mimeType`.
  public static func isAccepted(mimeType: String, by accept: [String]) -> Bool {
    guard !accept.isEmpty else { return true }
    let essence = Self.essence(of: mimeType)
    let type = essence.split(separator: "/", maxSplits: 1).first.map(String.init) ?? essence
    for entry in accept {
      let pattern = Self.essence(of: entry)
      if pattern == "*/*" { return true }
      if pattern.hasSuffix("/*"), pattern.dropLast(2) == type, essence.contains("/") { return true }
      if pattern == essence { return true }
    }
    return false
  }

  /// The lowercased `type/subtype` of a MIME type, without its parameters.
  private static func essence(of mimeType: String) -> String {
    let withoutParameters = mimeType.split(separator: ";", maxSplits: 1, omittingEmptySubsequences: false).first ?? ""
    return withoutParameters.trimmingCharacters(in: .whitespaces).lowercased()
  }
}
