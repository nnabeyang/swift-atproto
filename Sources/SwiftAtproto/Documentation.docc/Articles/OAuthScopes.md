# OAuth scopes

Parse granted scopes once, then let the client refuse calls the session cannot
make.

## Overview

An AT Protocol OAuth session grants a set of scope strings. ``ScopesSet`` parses
them into the five structured kinds — ``RpcScope``, ``RepoScope``,
``BlobScope``, ``SpaceScope``, and ``IncludeScope`` — and keeps anything else, such as
``OAuthScope/atproto`` or ``OAuthScope/transitionGeneric``, as raw strings.

```swift
let scopes = try ScopesSet(grantedScopeStrings, permissionSets: [MyAppPermissions.self])
```

Two initializers exist because the two situations differ. ``ScopesSet/init(_:permissionSets:)``
throws on a malformed scope, which is what you want when validating your own
authorization request. ``ScopesSet/init(rawScopes:permissionSets:)`` silently
drops what it cannot parse, which is what you want for a token issued by a
server that may know scopes this library does not.

## Include scopes are expanded at construction

``IncludeScope`` names a permission set by NSID rather than listing permissions.
Constructing a ``ScopesSet`` expands each include against the
``LexPermissionSet`` types you pass in, adding the resulting `rpc`, `repo`, and `space`
scopes to the set. An include may only grant permissions under its own
authority: a permission naming an NSID outside the include's namespace is
rejected.

## Checking a grant

``ScopesSet`` answers the four questions a request can raise:

- ``ScopesSet/allowsRpc(lxm:aud:)`` — may this method be called against this
  audience?
- ``ScopesSet/allowsRepo(collection:action:)`` — may this collection be written
  with this action?
- ``ScopesSet/allowsBlob(mime:)`` — may a blob of this MIME type be uploaded?
- ``ScopesSet/allowsSpace(_:grantedBy:spaceTypes:)`` — may an account read or
  write records in a permissioned space, request a delegation token, or manage
  the space?

``ScopesSet/hasAtprotoScope`` and ``ScopesSet/hasTransitionGeneric`` report the
two broad grants used by existing structured checks. `transition:generic` does
not grant access to permissioned spaces.

Space requirements are evaluated explicitly by the consumer. Pass the current
``LexSpace`` declarations when a scope omits `collection`; this resolves the
declaration's collection defaults at evaluation time rather than freezing them
when the scope is parsed. A space credential is a separate credential class and
does not pass through OAuth scope evaluation.

## Enforcement in the client

You rarely call those methods yourself. A client that returns a session from
`_XRPCCallable.oauthSession` gets the checks applied automatically before each
request, throwing ``OAuthScopeError`` rather than sending a call the server
would reject. A client that returns `nil` — a legacy app-password session — is
not scope-checked at all.

For a procedure input to be repo-checked it must describe its own writes by
conforming to ``RepoWriteOperationDescribing``, returning one
``RepoWriteRequirement`` per collection and ``LexPermissionAction`` it performs.
See <doc:MakingXRPCCalls>.

Generated Permissioned Data methods do not declare their endpoint-specific
authorization policy. A consumer maps generated inputs to
``SpaceScopeRequirement`` values and decides whether OAuth or a space credential
is appropriate before calling the generated method.
