# ``ATProtoCrypto``

Signing keys and DID identifiers for the AT Protocol.

## Overview

`ATProtoCrypto` covers the cryptographic side of AT Protocol identity: the
three key types the protocol recognizes, their `did:key` and multibase
encodings, signature verification, and the DID document types that publish
them.

It is independent of the XRPC runtime in `SwiftAtproto` — nothing here makes
network requests. Resolving a DID to a document is the caller's job; this module
parses the result and gets a usable ``PublicKey`` out of it.

```swift
let key = try PrivateKey(type: .p256)
let signature = try key.sign(message)
key.publicKey.isValidSignature(signature: signature, for: message)  // true
key.publicKey.did                                                   // "did:key:z..."
```

## Topics

### Keys

- <doc:SigningAndVerifying>
- ``KeyType``
- ``PrivateKey``
- ``PublicKey``

### Credentials

- <doc:ClientAttestations>
- ``ClientAttestation``

### Identifiers

- ``DID``
- ``DIDError``

### DID documents

- ``Document``
- ``VerificationMethod``
- ``Service``

### Errors

- ``VarintError``
