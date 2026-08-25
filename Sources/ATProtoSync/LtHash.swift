import Crypto
import Foundation

/// A homomorphic set hash used by Permissioned Data repositories.
///
/// Each UTF-8 element expands through BLAKE3 XOF into 1024 little-endian
/// `UInt16` lanes. Adding and removing elements uses wrapping arithmetic, so
/// the resulting state depends on the current multiset rather than operation
/// order.
public struct LtHash: Hashable, Sendable {
  /// The serialized size of an LtHash state.
  public static let stateByteCount = 2048

  private static let laneCount = stateByteCount / MemoryLayout<UInt16>.size
  private var lanes: [UInt16]

  /// Creates an empty LtHash state.
  public init() {
    lanes = [UInt16](repeating: 0, count: Self.laneCount)
  }

  /// Restores a previously serialized LtHash state.
  ///
  /// - Throws: ``RepoVerificationError/invalidLtHashStateLength(actual:)``
  ///   unless `state` contains exactly 2048 bytes.
  public init(state: Data) throws {
    guard state.count == Self.stateByteCount else {
      throw RepoVerificationError.invalidLtHashStateLength(actual: state.count)
    }
    lanes = stride(from: 0, to: state.count, by: 2).map { offset in
      UInt16(state[offset]) | (UInt16(state[offset + 1]) << 8)
    }
  }

  /// The complete 2048-byte little-endian state for persistence.
  public var state: Data {
    var bytes = [UInt8]()
    bytes.reserveCapacity(Self.stateByteCount)
    for lane in lanes {
      bytes.append(UInt8(truncatingIfNeeded: lane))
      bytes.append(UInt8(truncatingIfNeeded: lane >> 8))
    }
    return Data(bytes)
  }

  /// The SHA-256 digest compared with a signed commit's `hash` field.
  public var digest: Data {
    Data(SHA256.hash(data: state))
  }

  /// Whether every lane is zero.
  public var isEmpty: Bool {
    lanes.allSatisfy { $0 == 0 }
  }

  /// Adds one UTF-8 element to the multiset.
  public mutating func add(_ element: String) {
    combine(element, adding: true)
  }

  /// Removes one UTF-8 element from the multiset.
  public mutating func remove(_ element: String) {
    combine(element, adding: false)
  }

  private mutating func combine(_ element: String, adding: Bool) {
    let expanded = BLAKE3.hash(
      Data(element.utf8), outputByteCount: Self.stateByteCount)
    for laneIndex in lanes.indices {
      let offset = laneIndex * 2
      let value = UInt16(expanded[offset]) | (UInt16(expanded[offset + 1]) << 8)
      lanes[laneIndex] = adding ? lanes[laneIndex] &+ value : lanes[laneIndex] &- value
    }
  }
}
