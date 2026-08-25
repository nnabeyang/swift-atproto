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

The original `response(_:)` transport requirement returns only `Data` and
remains sufficient for clients that handle HTTP failures themselves. A
transport that wants the runtime to inspect a failure overrides
`responseWithMetadata(_:)` and returns ``XRPCResponseComponents`` for success
and failure responses alike. Network and transport failures still throw.

## Authorize the complete request

``XRPCRequestAuthorizer`` receives the complete request after any
`atproto-proxy` header has been applied. It also receives the resolved service
endpoint, so it can combine that base URL with the request's relative path and
build the absolute `htu` of a DPoP proof. Its `async throws` boundary allows the
implementation to load a signing key and generate a fresh proof before every
attempt.

``ATPClientProtocol`` conforms to the authorizer protocol. Its default
implementation preserves existing clients by reading the raw token from
``ATPClientProtocol/getAuthorization(endpoint:)`` and applying it as
`Authorization: Bearer <token>`. A client that needs permissioned data overrides
the authorizer method and can select an ``XRPCCredential`` from both the logical
destination and the NSID:

```swift
func authorize(
  _ request: XRPCRequestComponents,
  serviceEndpoint: URL
) async throws -> XRPCRequestComponents {
  var request = request
  let credential = try await credentials.credential(for: request.destination)

  switch credential {
  case .spaceDelegationToken(let token):
    request.headers[.authorization] = "Bearer \(token)"
    request.headers[.dpop] = try await proof(for: request, at: serviceEndpoint)
  case .spaceCredential(let token):
    request.headers[.authorization] = "DPoP \(token)"
    request.headers[.dpop] = try await proof(for: request, at: serviceEndpoint)
  default:
    break
  }
  return request
}
```

The proof crosses this boundary as a `String`. It may come from
`ATProtoCrypto`, an OAuth package, or another producer; `SwiftAtproto` does not
depend on a cryptography implementation. A client attestation is also a
distinct credential case, but it belongs in the `getSpaceCredential` request
body rather than an authorization header.

## Retry a DPoP nonce challenge

When a metadata response is unsuccessful, carries the `use_dpop_nonce` error,
and includes a nonempty `DPoP-Nonce` header, the runtime offers that nonce to
``XRPCRequestAuthorizer/storeDPoPNonce(_:for:serviceEndpoint:)``. Returning
`true` promises that the next authorization pass will build a new proof with
the stored nonce. The runtime then authorizes the original request components
again and sends one retry.

A second challenge is returned as the method's error without another store or
retry. Missing headers, unrelated errors, and authorizers that return `false`
also stop after the first response. Procedure bodies are immutable `Data` in
``XRPCRequestComponents``, so the retry reuses the exact encoded bytes only
after the server has explicitly rejected the first proof.

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
