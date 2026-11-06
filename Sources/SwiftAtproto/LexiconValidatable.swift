import Foundation

/// A generated type whose values can be checked against the constraints its
/// Lexicon declares before they are sent.
///
/// Code generation conforms every object, record, and union to this protocol,
/// and implements ``validateConstraints()`` for those that declare a
/// constraint or hold a value that may. The implementation visits the values
/// nested in the value, so calling it on a record checks the whole record. See
/// <doc:DecodingLexiconRecords>.
///
/// The method isn't named `validate()` because a Lexicon may declare a field
/// of that name: the input of `com.atproto.repo.createRecord` does.
public protocol LexiconValidatable {
  /// Checks this value, and the values nested in it, against the constraints
  /// their Lexicons declare.
  ///
  /// Reports the same violation as decoding the value in
  /// ``LexiconDecodingMode/strict`` would, without encoding it.
  ///
  /// - Throws: ``LexiconConstraintError`` for the first violation found.
  func validateConstraints() throws(LexiconConstraintError)
}

extension LexiconValidatable {
  /// Does nothing: a type that neither declares a constraint nor holds a
  /// value that may has nothing to check.
  ///
  /// Code generation relies on this so that it emits
  /// ``validateConstraints()`` only for the types that need it, and so that a
  /// hand-written ``ATProtoRecord`` keeps compiling.
  public func validateConstraints() throws(LexiconConstraintError) {}
}
