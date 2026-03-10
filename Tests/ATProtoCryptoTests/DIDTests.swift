import XCTest

@testable import ATProtoCrypto

class DIDTests: XCTestCase {
  func testDidDoc() throws {
    let json = """
      {
        "@context": [
          "https://www.w3.org/ns/did/v1",
          "https://w3id.org/security/multikey/v1",
          "https://w3id.org/security/suites/secp256k1-2019/v1"
        ],
        "id": "did:plc:yk4dd2qkboz2yv6tpubpc6co",
        "alsoKnownAs": [
          "at://dholms.xyz"
        ],
        "verificationMethod": [
          {
            "id": "did:plc:yk4dd2qkboz2yv6tpubpc6co#atproto",
            "type": "Multikey",
            "controller": "did:plc:yk4dd2qkboz2yv6tpubpc6co",
            "publicKeyMultibase": "zQ3shXjHeiBuRCKmM36cuYnm7YEMzhGnCmCyW92sRJ9pribSF"
          }
        ],
        "service": [
          {
            "id": "#atproto_pds",
            "type": "AtprotoPersonalDataServer",
            "serviceEndpoint": "https://bsky.social"
          }
        ]
      }  
      """
    let decoder = JSONDecoder()
    let doc = try decoder.decode(Document.self, from: Data(json.utf8))
    let pk = try doc.getPublicKey(id: "#atproto")
    XCTAssertEqual(pk.did, "did:key:zQ3shXjHeiBuRCKmM36cuYnm7YEMzhGnCmCyW92sRJ9pribSF")
  }

  func testSig() throws {
    let json = """
      {
        "id": "#atproto",
        "type": "EcdsaSecp256k1VerificationKey2019",
        "controller": "did:plc:wj5jny4sq4sohwoaxjkjgug6",
        "publicKeyMultibase": "zQYEBzXeuTM9UR3rfvNag6L3RNAs5pQZyYPsomTsgQhsxLdEgCrPTLgFna8yqCnxPpNT7DBk6Ym3dgPKNu86vt9GR"
      }
      """

    let vm = try JSONDecoder().decode(VerificationMethod.self, from: Data(json.utf8))
    let pubKey = try vm.publicKey
    XCTAssertEqual(pubKey.type, .secp256k1)
    XCTAssertEqual(pubKey.did, "did:key:zQ3shXjHeiBuRCKmM36cuYnm7YEMzhGnCmCyW92sRJ9pribSF")
  }
}
