# Third-party notices

## BLAKE3

`ATProtoSync` depends on the portable C implementation from BLAKE3 1.8.7,
packaged for SwiftPM as version `1.8.7-swift.1`:

- Source: https://github.com/BLAKE3-team/BLAKE3/tree/1.8.7/c
- Swift package: https://github.com/nnabeyang/BLAKE3/tree/1.8.7-swift.1
- License: Apache License 2.0
- License text: https://github.com/nnabeyang/BLAKE3/blob/1.8.7-swift.1/LICENSE_A2

## STAR interop test vectors

`ATProtoSyncTests` runs the interop test vectors of the STAR specification
(https://dasl.ing/star.html), copied unchanged into
`Tests/ATProtoSyncTests/Fixtures/STARInterop`. They are used only by the tests.

- Source: https://tangled.org/microcosm.blue/star/tree/41bdec1fd1be7f6f30a1f961a01442b2fa2ec3c1/interop
- Copyright (c) 2026 microcosm
- License: MIT License or Apache License 2.0, at your option
- License text: `LICENSE.MIT` and `LICENSE.Apache-2.0` in the source repository
