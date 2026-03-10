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
