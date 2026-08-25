import CBLAKE3
import Foundation

enum BLAKE3 {
  static func hash(_ input: Data, outputByteCount: Int) -> Data {
    precondition(outputByteCount >= 0)

    var hasher = blake3_hasher()
    blake3_hasher_init(&hasher)
    input.withUnsafeBytes { bytes in
      blake3_hasher_update(&hasher, bytes.baseAddress, bytes.count)
    }

    var output = [UInt8](repeating: 0, count: outputByteCount)
    output.withUnsafeMutableBytes { bytes in
      blake3_hasher_finalize(
        &hasher,
        bytes.baseAddress?.assumingMemoryBound(to: UInt8.self),
        bytes.count
      )
    }
    return Data(output)
  }
}
