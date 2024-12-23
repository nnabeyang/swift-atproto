import Foundation
import SwiftParser
import SwiftSyntax
import SwiftSyntaxBuilder
import XCTest
@testable import SwiftAtproto

struct XRPCBaseClient: XRPCClientProtocol {
    var serviceEndpoint: URL

    var decoder: JSONDecoder

    var auth: SwiftAtproto.AuthInfo

    func tokenIsExpired(error _: SwiftAtproto.UnExpectedError) -> Bool {
        fatalError()
    }

    func getAuthorization(endpoint _: String) -> String {
        fatalError()
    }

    func refreshSession() async -> Bool {
        fatalError()
    }

    func signout() {
        fatalError()
    }
}

final class SwiftAtprotoTests: XCTestCase {
    func testMakeParameters() throws {
        let items = XRPCBaseClient.makeParameters(params: ["param1[]": ["1", "2", "3"], "param2": "hello"])
        XCTAssertEqual(items.map(\.description).sorted(), ["param1[]=1", "param1[]=2", "param1[]=3", "param2=hello"])
    }

    func testLexLinkCodable() throws {
        let json = #"{"$link":"bafkreibme22gw2h7y2h7tg2fhqotaqjucnbc24deqo72b6mkl2egezxhvy"}"#
        let decoder = JSONDecoder()
        let link = try decoder.decode(LexLink.self, from: Data(json.utf8))
        XCTAssertEqual(link.toBaseEncodedString, "bafkreibme22gw2h7y2h7tg2fhqotaqjucnbc24deqo72b6mkl2egezxhvy")
        let encoder = JSONEncoder()
        encoder.dataEncodingStrategy = XRPCBaseClient.dataEncodingStrategy
        XCTAssertEqual(try String(decoding: encoder.encode(link), as: UTF8.self), json)
    }

    func testUnknownRecordCodable() throws {
        let json = #"{"$type":"com.nnabeyang.unknown"}"#
        let decoder = JSONDecoder()
        let record = try decoder.decode(UnknownRecord.self, from: Data(json.utf8))
        XCTAssertEqual(record.type, "com.nnabeyang.unknown")
        let encoder = JSONEncoder()
        encoder.dataEncodingStrategy = XRPCBaseClient.dataEncodingStrategy
        XCTAssertEqual(try String(decoding: encoder.encode(record), as: UTF8.self), json)
    }
}
