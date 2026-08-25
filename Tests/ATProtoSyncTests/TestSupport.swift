import Foundation

extension Data {
  init(hex: String) {
    precondition(hex.count.isMultiple(of: 2))
    self.init(
      stride(from: 0, to: hex.count, by: 2).map { offset in
        let start = hex.index(hex.startIndex, offsetBy: offset)
        let end = hex.index(start, offsetBy: 2)
        return UInt8(hex[start..<end], radix: 16)!
      })
  }

  var hex: String {
    map { String(format: "%02x", $0) }.joined()
  }
}
