# Making XRPC calls

Implement one transport method and get every generated request as a type-safe
call.

## Overview

Generated request types describe *what* to send: an ``XRPCQuery`` carries its
parameters in a query string, an ``XRPCProcedure`` carries an encoded body, and
both declare the response body they decode into. They say nothing about *how*
bytes travel, which is what a client supplies.

## Conform to a client protocol

`_XRPCCallable` is the smallest thing a client can be. Its only unimplemented
requirement is `_XRPCCallable.response(_:)`, which turns request components
into raw response `Data`:

```swift
func response(_ requestComponents: XRPCRequestComponents) async throws -> Data
```

Everything else follows from it. The protocol extension implements
`_XRPCCallable.call(_:input:)` for queries and procedures, so once
`_XRPCCallable.response(_:)` exists every generated method is callable.

``ATPClientProtocol`` refines it for clients that talk to a single service. It
adds ``ATPClientProtocol/serviceEndpoint``, a `JSONDecoder`, and the session
hooks — ``ATPClientProtocol/getAuthorization(endpoint:)``,
``ATPClientProtocol/tokenIsExpired(error:)``, and
``ATPClientProtocol/refreshSession()`` — that a transport needs in order to
attach credentials and retry once after a refresh.

## Build the request

``XRPCRequestComponents`` is the whole request in transport-neutral form: the
NSID, query items, `HTTPFields` headers, method, an optional body, and an
optional ``XRPCRequestDestination``. Its
``XRPCRequestComponents/relativePath`` is `/xrpc/<nsid>`, which you join to your
service endpoint.

Queries are encoded as percent-escaped query items and sent as `GET`.
Procedures are sent as `POST`; the body is the JSON encoding of the input,
except for two cases that pass through unchanged — a `Data` input, and an
``XRPCBlobUpload``, whose `mimeType` becomes the `Content-Type` header.

Responses are decoded with the AT Protocol data encoding strategy and with
``LexiconDecodingMode/permissive``, so a server that exceeds an authoring
constraint does not break decoding. See <doc:DecodingLexiconRecords>.

## Route to repo and space hosts

Permissioned data has no relay, so one client may need to call its default PDS,
a space authority's host, and each member's repository host. Implement
``DIDDocumentResolver/resolveDIDDocument(for:)`` and use its host helpers to
derive a destination from the appropriate DID:

```swift
let repoHost = try await resolver.resolveRepoHost(for: memberDID)
let repo = try await client.call(
  ComAtprotoSpaceGetRepo.self,
  input: input,
  destination: repoHost
)
```

``DIDDocumentResolver/resolveRepoHost(for:)`` derives the endpoint from
``DIDDocument/pdsUrl``. ``DIDDocumentResolver/resolveSpaceHost(for:)`` uses
``DIDDocument/spaceHostUrl``, including its PDS fallback. The destination keeps
the logical host kind and DID even when both resolve to the same URL, allowing a
request authorizer to select the appropriate credential.

The destination arrives unchanged in `response(_:)`. A transport that also
conforms to ``ATPClientProtocol`` chooses its base URL without changing the
existing default path:

```swift
let endpoint = requestComponents.destination?.serviceEndpoint ?? serviceEndpoint
```

Calls that omit `destination` leave it `nil`, so generated method signatures and
single-host clients continue to use ``ATPClientProtocol/serviceEndpoint``.
Resolver implementations own caching and invalidation of DID documents or
resolved destinations.

## Route through a proxy

`_XRPCCallable.getProxy(nsid:)` is asked for the target service before each
call. Returning a non-`nil` value sets the `atproto-proxy` header, which is how
a request reaches an AppView or labeler other than the user's PDS. The default
implementation on ``ATPClientProtocol`` returns `nil`, meaning no proxying.

## Scope enforcement

When `_XRPCCallable.oauthSession` is `nil` no scope checking happens — a
legacy session sends whatever it is asked to send. When a session is present,
its `grantedScopes` are checked before the request leaves the process and an
``OAuthScopeError`` is thrown instead of making a call that would be rejected:

- Every proxied call checks `rpc` scope for the method's NSID and audience.
- An input conforming to ``RepoWriteOperationDescribing`` checks `repo` scope
  for each collection and action it declares.
- An ``XRPCBlobUpload`` input checks `blob` scope for its MIME type.

Note that the `rpc` check only runs for calls that carry a proxy audience.
See <doc:OAuthScopes>.
