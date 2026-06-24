import CID

extension LexLink: LexiconStringFormat {
  public init(string: String) throws {
    self = try CID(string)
  }

  public var rawValue: String { toBaseEncodedString }
}
