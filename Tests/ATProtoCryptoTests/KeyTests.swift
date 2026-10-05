import Multibase
import XCTest

@testable import ATProtoCrypto

final class KeyTests: XCTestCase {
  func testRawRepresentation_secp256k1() throws {
    let rawValue = try PrivateKey(type: .secp256k1).rawRepresentation
    let privKey = try PrivateKey(type: .secp256k1, rawValue: rawValue)
    XCTAssertEqual(privKey.rawRepresentation, rawValue)
  }

  func testRawRepresentation_ed25519() throws {
    let rawValue = try PrivateKey(type: .ed25519).rawRepresentation
    let privKey = try PrivateKey(type: .ed25519, rawValue: rawValue)
    XCTAssertEqual(privKey.rawRepresentation, rawValue)
  }

  func testRawRepresentation_p256() throws {
    let rawValue = try PrivateKey(type: .p256).rawRepresentation
    let privKey = try PrivateKey(type: .p256, rawValue: rawValue)
    XCTAssertEqual(privKey.rawRepresentation, rawValue)
  }

  func testPublicKeyFromMultibaseString_p256() throws {
    let multibaseString = try PrivateKey(type: .p256).publicKey.multibaseString
    let pubKey = try PublicKey.publicKeyFromMultibaseString(string: multibaseString)
    XCTAssertEqual(pubKey.type, .p256)
    XCTAssertEqual(pubKey.multibaseString, multibaseString)
  }

  // The P-256 multikey example from https://atproto.com/specs/cryptography.
  func testPublicKeyFromMultibaseString_p256SpecExample() throws {
    let multibaseString = "zDnaembgSGUhZULN2Caob4HLJPaxBh92N7rtH21TErzqf8HQo"
    let pubKey = try PublicKey.publicKeyFromMultibaseString(string: multibaseString)
    XCTAssertEqual(pubKey.type, .p256)
    XCTAssertEqual(pubKey.multibaseString, multibaseString)
    XCTAssertEqual(pubKey.did, "did:key:\(multibaseString)")
  }

  func testMultibaseString_p256IsCompressed() throws {
    let pubKey = try PrivateKey(type: .p256).publicKey
    let decoded = try BaseEncoding.decode(pubKey.multibaseString).data
    XCTAssertEqual(Array(decoded.prefix(2)), [0x80, 0x24])
    XCTAssertEqual(decoded.count, 2 + 33)
    XCTAssertTrue(pubKey.multibaseString.hasPrefix("zDn"))
    XCTAssertTrue(pubKey.did.hasPrefix("did:key:zDn"))
  }

  // Earlier releases wrote the 64-byte coordinates after the multicodec prefix.
  func testPublicKeyFromMultibaseString_p256LegacyCoordinates() throws {
    let sk = try PrivateKey(type: .p256)
    let legacy = BaseEncoding.base58btc.encode(data: Data([0x80, 0x24]) + sk.publicKey.rawBytes)
    let pubKey = try PublicKey.publicKeyFromMultibaseString(string: legacy)
    XCTAssertEqual(pubKey.multibaseString, sk.publicKey.multibaseString)
    let msg = Data("legacy p256".utf8)
    XCTAssertTrue(pubKey.isValidSignature(signature: try sk.sign(msg), for: msg))
  }

  func testDecodedP256KeyVerifiesSignature() throws {
    let sk = try PrivateKey(type: .p256)
    let pubKey = try PublicKey.publicKeyFromMultibaseString(string: sk.publicKey.multibaseString)
    let msg = Data("compressed p256".utf8)
    XCTAssertTrue(pubKey.isValidSignature(signature: try sk.sign(msg), for: msg))
    XCTAssertEqual(try pubKey.jwkThumbprint, try sk.publicKey.jwkThumbprint)
    XCTAssertEqual(pubKey.rawBytes, sk.publicKey.rawBytes)
  }

  func testPublicKeyFromMultibaseString_secp256k1() throws {
    let multibaseString = try PrivateKey(type: .secp256k1).publicKey.multibaseString
    let pubKey = try PublicKey.publicKeyFromMultibaseString(string: multibaseString)
    XCTAssertEqual(pubKey.type, .secp256k1)
    XCTAssertEqual(pubKey.multibaseString, multibaseString)
  }

  func testPublicKeyFromMultibaseString_ed25519() throws {
    let multibaseString = try PrivateKey(type: .ed25519).publicKey.multibaseString
    let pubKey = try PublicKey.publicKeyFromMultibaseString(string: multibaseString)
    XCTAssertEqual(pubKey.type, .ed25519)
    XCTAssertEqual(pubKey.multibaseString, multibaseString)
  }

  func testIsValidSignature_p256() throws {
    let sk = try PrivateKey(type: .p256)
    let pk = sk.publicKey
    let msg = Data("foo bar beeep boop bop".utf8)
    let sig = try sk.sign(msg)
    XCTAssertTrue(pk.isValidSignature(signature: sig, for: msg))
  }

  func testIsValidSignature_secp256k1() throws {
    let sk = try PrivateKey(type: .secp256k1)
    let pk = sk.publicKey
    let msg = Data("foo bar beeep boop bop".utf8)
    let sig = try sk.sign(msg)
    XCTAssertTrue(pk.isValidSignature(signature: sig, for: msg))
  }

  func testIsValidSignature_ed25519() throws {
    let sk = try PrivateKey(type: .ed25519)
    let pk = sk.publicKey
    let msg = Data("foo bar beeep boop bop".utf8)
    let sig = try sk.sign(msg)
    XCTAssertTrue(pk.isValidSignature(signature: sig, for: msg))
  }
}
