//
//  MacrosTests.swift
//  SwiftAtproto
//
//  Created by Noriaki Watanabe on 2024/12/23.
//

#if os(macOS)
    import SwiftSyntax
    import SwiftSyntaxBuilder
    import SwiftSyntaxMacros
    import SwiftSyntaxMacrosTestSupport
    import XCTest
    @testable import Macros

    final class MacroExampleTests: XCTestCase {
        func testXRPCClientMacro() throws {
            let testMacros: [String: Macro.Type] = [
                "XRPCClientMacro": XRPCClientMacro.self,
            ]

            assertMacroExpansion(
                """
                @XRPCClientMacro
                public struct TestClient {
                  let host: URL
                  public var auth: AuthInfo
                  public var serviceEndpoint: URL {
                    auth.serviceEndPoint ?? host
                  }
                  public let decoder: JSONDecoder
                }
                """,
                expandedSource: """
                public struct TestClient {
                  let host: URL
                  public var auth: AuthInfo
                  public var serviceEndpoint: URL {
                    auth.serviceEndPoint ?? host
                  }
                  public let decoder: JSONDecoder

                  private init(host: URL, auth: AuthInfo) {
                    self.host = host
                    self.auth = auth
                    decoder = JSONDecoder()
                    Self.setModuleName()
                  }
                }

                extension TestClient: XRPCClientProtocol {
                }
                """,
                macros: testMacros,
                indentationWidth: .spaces(2)
            )
        }
    }
#endif
