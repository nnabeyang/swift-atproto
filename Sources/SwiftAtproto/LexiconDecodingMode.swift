import Foundation

/// Controls whether generated lexicon models enforce authoring constraints while decoding.
public enum LexiconDecodingMode: Sendable {
  /// Enforces all generated constraints. This is the default for standalone decoders.
  case strict
  /// Accepts wire-compatible values even when they exceed authoring constraints.
  case permissive

  public static func shouldValidateConstraints(in decoder: any Decoder) -> Bool {
    let mode = decoder.userInfo[.atprotoLexiconDecodingMode] as? Self ?? .strict
    return mode == .strict
  }
}

extension CodingUserInfoKey {
  /// Selects the constraint validation behavior for generated lexicon models.
  public static let atprotoLexiconDecodingMode = CodingUserInfoKey(
    rawValue: "com.nnabeyang.swift-atproto.lexicon-decoding-mode"
  )!
}
