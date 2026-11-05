import Foundation

/// A value that violates a constraint its Lexicon declares.
///
/// Thrown by ``LexiconValidatable/validateConstraints()``, and while decoding
/// in ``LexiconDecodingMode/strict``, where it is wrapped in
/// `DecodingError.dataCorrupted` as the underlying error; see
/// <doc:DecodingLexiconRecords>. Each case names the field it applies to, and
/// carries the limit the field exceeded.
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
}
