import Foundation

public struct XRPCBlobUpload: Codable, Sendable, Hashable {
  public let data: Data
  public let mimeType: String

  public init(data: Data, mimeType: String) {
    self.data = data
    self.mimeType = mimeType
  }
}
