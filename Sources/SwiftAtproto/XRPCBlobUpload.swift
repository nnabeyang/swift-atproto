import Foundation

/// Binary data to upload as a blob.
///
/// Passing this as a procedure input sends the bytes unchanged and uses
/// ``mimeType`` as the `Content-Type`, bypassing JSON encoding. When the client
/// has an OAuth session, the MIME type is checked against its granted `blob`
/// scope before the request is sent.
public struct XRPCBlobUpload: Codable, Sendable, Hashable {
  /// The bytes to upload.
  public let data: Data
  /// The MIME type of ``data``, sent as the `Content-Type` header.
  public let mimeType: String

  public init(data: Data, mimeType: String) {
    self.data = data
    self.mimeType = mimeType
  }
}
