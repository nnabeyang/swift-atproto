import Foundation

/// A value that violates a constraint its Lexicon declares.
///
/// Thrown by ``LexiconValidatable/validateConstraints()``, and while decoding
/// in ``LexiconDecodingMode/strict``, where it is wrapped in
/// `DecodingError.dataCorrupted` as the underlying error; see
/// <doc:DecodingLexiconRecords>. Each case names the field it applies to, and
/// carries the limit the field exceeded. An element of an array is named with
/// its position, such as `tags[2]`.
public enum LexiconConstraintError: Error {
  case stringTooLong(_ field: String, limit: Int)
  case stringTooShort(_ field: String, minimum: Int)
  case tooManyGraphemes(_ field: String, limit: Int)
  case tooFewGraphemes(_ field: String, minimum: Int)
  case integerBelowMinimum(_ field: String, minimum: Int)
  case integerAboveMaximum(_ field: String, maximum: Int)
  case arrayTooLong(_ field: String, limit: Int)
  case arrayTooShort(_ field: String, minimum: Int)
  case bytesTooLong(_ field: String, limit: Int)
  case bytesTooShort(_ field: String, minimum: Int)
  case blobTooLarge(_ field: String, limit: Int)
  /// The field isn't the value its Lexicon fixes with `const`. `expected` is
  /// that value as text, such as `"true"` or `"42"`.
  case notConstant(_ field: String, expected: String)
  /// The blob's MIME type is none that the field's `accept` list allows; see
  /// ``LexBlob/isAccepted(mimeType:by:)``.
  case blobTypeNotAccepted(_ field: String, accepted: [String])
}
