//
//  ATProtoMacro.swift
//  SwiftAtproto
//
//  Created by Noriaki Watanabe on 2024/12/23.
//

import SwiftAtproto

@attached(member, names: named(init))
@attached(extension, conformances: XRPCClientProtocol)
public macro XRPCClient() = #externalMacro(module: "Macros", type: "XRPCClientMacro")
