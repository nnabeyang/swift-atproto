//
//  ATProtoMacro.swift
//  SwiftAtproto
//
//  Created by Noriaki Watanabe on 2024/12/23.
//

import SwiftAtproto

@available(*, deprecated, message: "Use the code-generated `XRPCClientProtocol` instead. `_XRPCClientProtocol` only provides internal infrastructure and lacks XRPC API method requirements.")
@attached(member, names: named(init))
@attached(extension, conformances: _XRPCClientProtocol)
public macro XRPCClient() = #externalMacro(module: "Macros", type: "XRPCClientMacro")
