import Foundation
import Testing

@testable import ATProtoCrypto

struct JWKThumbprintTests {
  // MARK: - RFC 7638

  // The only worked example in RFC 7638 is the RSA key in §3.1. The AT Protocol
  // key types are all EC or OKP, so the vector is fed to the shared core to check
  // the algorithm itself — member order, whitespace-free JSON, SHA-256, base64url.
  @Test func matchesTheRFC7638WorkedExample() {
    let modulus =
      "0vx7agoebGcQSuuPiLJXZptN9nndrQmbXEps2aiAFbWhM78LhWx4cbbfAAtVT86zwu1RK7aPFFxuhDR1L6tSoc"
      + "_BJECPebWKRXjBZCiFV4n3oknjhMstn64tZ_2W-5JsGY4Hc5n9yBXArwl93lqt7_RN5w6Cf0h4QyQ5v-65YGjQ"
      + "R0_FDW2QvzqY368QQMicAtaSqzs8KJZgnYb9c7d0zgdAZHzu6qMQvRL5hajrn1n91CbOpbISD08qNLyrdkt-bF"
      + "TWhAI4vMQFh6WeZu0fM4lFd2NcRwr3XPksINHaQ-G_xBniIqbw0Ls1jF44-csFCur-kEgU8awapJzKnqDKgw"
    let thumbprint = PublicKey.thumbprint(members: [
      ("e", "AQAB"),
      ("kty", "RSA"),
      ("n", modulus),
    ])
    #expect(thumbprint == "NzbLsXh8uDCcd-6MNwXF4W_7noWXFZAfHkxZsRGC9Xs")
  }

  // MARK: - base64url

  @Test func base64URLUsesTheURLSafeAlphabetWithoutPadding() {
    // 0xFB 0xFF encodes as "+/8=" in the standard alphabet, exercising both
    // substitutions and the padding strip in one vector.
    #expect(base64URLEncoded(Data([0xFB, 0xFF])) == "-_8")
    #expect(base64URLEncoded(Data()) == "")
    #expect(base64URLEncoded(Data([0x00])) == "AA")
  }

  // MARK: - Key types

  // `KeyType` is not `Sendable`, so these iterate a local list rather than going
  // through `@Test(arguments:)`.
  private var keyTypes: [KeyType] { [.p256, .secp256k1, .ed25519] }

  @Test func thumbprintIsA43CharacterBase64URLDigest() throws {
    for type in keyTypes {
      let thumbprint = try PrivateKey(type: type).publicKey.jwkThumbprint
      // SHA-256 is 32 bytes, which is 43 base64 characters once padding is dropped.
      #expect(thumbprint.count == 43)
      #expect(!thumbprint.contains("+"))
      #expect(!thumbprint.contains("/"))
      #expect(!thumbprint.contains("="))
    }
  }

  @Test func thumbprintIsStableForOneKeyAndDistinctBetweenKeys() throws {
    for type in keyTypes {
      let key = try PrivateKey(type: type).publicKey
      #expect(try key.jwkThumbprint == key.jwkThumbprint)
      let other = try PrivateKey(type: type).publicKey
      #expect(try key.jwkThumbprint != other.jwkThumbprint)
    }
  }

  // The thumbprint covers the key, not the encoding it arrived in, so a key read
  // back from its `did:key` form has to agree with the one it came from.
  @Test func thumbprintSurvivesAMultibaseRoundTrip() throws {
    for type in keyTypes {
      let key = try PrivateKey(type: type).publicKey
      let restored = try PublicKey.publicKeyFromMultibaseString(string: key.multibaseString)
      #expect(try key.jwkThumbprint == restored.jwkThumbprint)
    }
  }

  // MARK: - Coordinates

  @Test func p256CoordinatesAreTheTwoHalvesOfTheRawRepresentation() throws {
    let key = try PrivateKey(type: .p256).publicKey
    let bytes = key.rawBytes
    #expect(bytes.count == 64)
    let expected = PublicKey.thumbprint(members: [
      ("crv", "P-256"),
      ("kty", "EC"),
      ("x", base64URLEncoded(bytes.prefix(32))),
      ("y", base64URLEncoded(bytes.suffix(32))),
    ])
    #expect(try key.jwkThumbprint == expected)
  }

  // `rawBytes` is the 33-byte compressed point, which carries `x` and a parity
  // bit; the coordinates come from re-serializing it uncompressed.
  @Test func secp256k1CoordinatesComeFromTheUncompressedPoint() throws {
    let key = try PrivateKey(type: .secp256k1).publicKey
    #expect(key.rawBytes.count == 33)
    guard case .secp256k1(let underlying) = key.raw else {
      Issue.record("expected a secp256k1 key")
      return
    }
    let uncompressed = try underlying.uncompressedBytes
    #expect(uncompressed.count == 65)
    #expect(uncompressed.first == 0x04)
    // The compressed form is the prefix byte plus `x`, so `x` has to agree.
    #expect(Array(uncompressed.dropFirst().prefix(32)) == Array(key.rawBytes.dropFirst()))
  }

  @Test func ed25519UsesTheOKPMemberSet() throws {
    let key = try PrivateKey(type: .ed25519).publicKey
    #expect(key.rawBytes.count == 32)
    let expected = PublicKey.thumbprint(members: [
      ("crv", "Ed25519"),
      ("kty", "OKP"),
      ("x", base64URLEncoded(key.rawBytes)),
    ])
    #expect(try key.jwkThumbprint == expected)
  }
}
