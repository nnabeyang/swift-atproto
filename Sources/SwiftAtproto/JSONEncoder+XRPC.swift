import Foundation

extension JSONEncoder.DataEncodingStrategy {
  internal static var xrpc: Self {
    .custom { data, encoder in
      do {
        if !data.isEmpty, data[0] == 0 {
          try LexLink.dataEncodingStrategy(data: data, encoder: encoder)
          return
        }
      } catch {}
      if let string = String(data: data, encoding: .utf8) {
        try string.encode(to: encoder)
      } else {
        try data.base64Encoded().encode(to: encoder)
      }
    }
  }
}
