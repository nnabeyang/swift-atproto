# ``SwiftAtproto``

Type-safe XRPC communication for the AT Protocol.

## Overview

`SwiftAtproto` is the runtime half of this package. It does not know about any
particular Lexicon: it defines the protocols that generated code conforms to,
the wire representations shared by every request, and the identifier types that
Lexicon string formats map onto.

The other half is code generation. `SwiftAtprotoLex` reads Lexicon JSON and
emits one `XRPCRequest` type per Lexicon method plus the client extensions that
call them. Those generated types conform to ``XRPCQuery`` and ``XRPCProcedure``
from this module, so the request and response bodies are checked at compile
time while the transport stays yours to implement.

To send requests you supply a single method — how to turn an
``XRPCRequestComponents`` value into response `Data` — and get every generated
call for free. See <doc:MakingXRPCCalls>.

```swift
let posts = try await client.call(
  AppBskyFeedGetPosts.self,
  input: .init(uris: [postURI])
)
```

## Topics

### Essentials

- <doc:MakingXRPCCalls>
- ``XRPCRequest``
- ``ATProtoRecord``

### Requests and responses

- ``XRPCQuery``
- ``XRPCQueryInput``
- ``XRPCInputQuery``
- ``XRPCProcedure``
- ``XRPCRequestComponents``
- ``XRPCResponseComponents``
- ``XRPCRequestDestination``
- ``XRPCRequestAuthorizer``
- ``XRPCCredential``
- ``XRPCBlobUpload``
- ``EmptyResponse``
- ``Parameters``
- ``ParamElement``

### Clients

- ``ATPClientProtocol``
- ``XRPCAuth``

### Lexicon string formats

- <doc:LexiconStringFormats>
- ``FormatString``
- ``LexiconStringFormat``
- ``AtIdentifier``
- ``DID``
- ``Handle``
- ``NSID``
- ``ATURI``
- ``TID``
- ``RecordKey``
- ``SpaceRef``
- ``URI``
- ``Language``
- ``AtprotoDatetimeFormatStyle``
- ``AtprotoDatetimeParseStrategy``

### OAuth scopes

- <doc:OAuthScopes>
- ``OAuthScope``
- ``OAuthSession``
- ``ScopesSet``
- ``RpcScope``
- ``RepoScope``
- ``BlobScope``
- ``IncludeScope``
- ``LexPermission``
- ``LexPermissionSet``
- ``LexPermissionAction``
- ``LexPermissionResource``
- ``RepoWriteOperationDescribing``
- ``RepoWriteRequirement``

### Space type declarations

- ``LexSpace``
- ``LexRecordKeyType``

### Space credentials

- <doc:SpaceCredentials>
- ``UnverifiedSpaceCredential``
- ``UnverifiedSpaceDelegationToken``
- ``UnverifiedClientAttestation``

### Event streams

- <doc:Subscriptions>
- ``XRPCSubscription``
- ``XRPCSubscriptionCallable``
- ``XRPCSubscriptionTransport``
- ``XRPCSubscriptionConfiguration``
- ``XRPCSubscriptionRequestComponents``
- ``XRPCWebSocketConnection``
- ``XRPCWebSocketRequest``
- ``XRPCWebSocketMessage``

### Decoding records

- <doc:DecodingLexiconRecords>
- ``LexiconDecodingMode``
- ``UnknownATPValueProtocol``
- ``UnknownRecord``
- ``AnyCodable``
- ``LexBlob``
- ``LexLink``

### Identity documents

- <doc:SpaceAuthorities>
- ``DIDDocument``
- ``DocService``
- ``DocVerificationMethod``
- ``DIDHandleResolver``
- ``DIDDocumentResolver``
- ``ServiceIdentifier``

### Errors

- ``XRPCError``
- ``UnExpectedError``
- ``LexiconConstraintError``
- ``LexiconStringFormatError``
- ``OAuthScopeError``
- ``SpaceTokenError``
- ``XRPCSubscriptionStreamError``
