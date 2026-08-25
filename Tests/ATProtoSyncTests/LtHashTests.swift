import Foundation
import Testing

@testable import ATProtoSync

@Suite("Permissioned repository LtHash")
struct LtHashTests {
  @Test func matchesTheProposalSnapshot() {
    var hash = LtHash()
    hash.add("one")
    hash.add("two")

    #expect(
      hash.digest.hex == "ae05cb6d224379d9710c290c8529945c5b0e0fde9ead30b9699057ce701c63e7")
  }

  @Test func emptyStateMatchesSHA256Vector() {
    let hash = LtHash()
    #expect(hash.state.count == 2048)
    #expect(hash.isEmpty)
    #expect(
      hash.digest.hex == "e5a00aa9991ac8a5ee3109844d84a55583bd20572ad3ffcd42792f3c36b183ad")
  }

  @Test func additionIsOrderIndependentAndRemovalRestoresState() {
    var forward = LtHash()
    forward.add("a")
    forward.add("b")

    var reverse = LtHash()
    reverse.add("b")
    reverse.add("a")
    #expect(forward == reverse)

    forward.remove("a")
    forward.remove("b")
    #expect(forward.isEmpty)
  }

  @Test func persistedStateDoesNotAliasItsSource() throws {
    var original = LtHash()
    original.add("a")
    let state = original.state
    var restored = try LtHash(state: state)
    restored.add("b")

    #expect(restored != original)
    #expect(try LtHash(state: state) == original)
  }

  @Test func rejectsWrongStateLength() {
    #expect(throws: RepoVerificationError.invalidLtHashStateLength(actual: 32)) {
      try LtHash(state: Data(repeating: 0, count: 32))
    }
  }
}
