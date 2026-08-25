# Subscribing to event streams

Consume a Lexicon subscription as an `AsyncThrowingStream`, over the WebSocket
transport of your choice.

## Overview

Lexicon `subscription` methods become ``XRPCSubscription`` types. A client that
conforms to ``XRPCSubscriptionCallable`` calls
``XRPCSubscriptionCallable/subscribe(_:input:)`` and receives decoded messages:

```swift
for try await message in client.subscribe(ComAtprotoSyncSubscribeRepos.self, input: .init(cursor: nil)) {
  handle(message)
}
```

Cancelling the task that consumes the stream tears the connection down.

## Supplying a transport

This module does not open sockets. ``XRPCSubscriptionTransport`` is the seam:
given an ``XRPCWebSocketRequest`` it returns an ``XRPCWebSocketConnection``,
which is an `AsyncThrowingStream` of ``XRPCWebSocketMessage`` values plus a
close operation. Backing it with `URLSessionWebSocketTask` on Apple platforms
and with a NIO-based client on Linux is the usual arrangement.

``ATPClientProtocol`` already implements
``XRPCSubscriptionCallable/prepareSubscriptionRequest(_:)`` for you: it appends
`xrpc/<nsid>` to the service endpoint, rewrites the scheme from `https` to `wss`
(or `http` to `ws`), attaches the query items, and passes the handshake headers
through ``XRPCRequestAuthorizer``. The default authorizer reads the raw token
from ``ATPClientProtocol/getAuthorization(endpoint:)`` and sends it as a Bearer
credential, matching ordinary XRPC calls.

## Frame handling

``XRPCSubscriptionConfiguration`` bounds the stream. `maximumFrameBytes`
(2 MiB by default) rejects an oversized frame with
``XRPCSubscriptionStreamError/frameTooLarge(limit:)``, and `bufferCapacity`
(16 by default) caps how many messages are buffered for a slow consumer.

AT Protocol event streams are binary. A text frame is a protocol violation and
terminates the stream with ``XRPCSubscriptionStreamError/textFrame``.

## Scope enforcement

Like unary calls, a subscription made through a client with an OAuth session is
checked against its granted `rpc` scope before connecting when the call carries
a proxy audience. See <doc:OAuthScopes>.
