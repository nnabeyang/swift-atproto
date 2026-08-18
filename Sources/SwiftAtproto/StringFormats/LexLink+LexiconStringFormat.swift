import CID

extension LexLink: LexiconStringFormat {
  public init(string: String) throws {
    self = try LexLink(string)
  }

  public var rawValue: String { toBaseEncodedString }
}
