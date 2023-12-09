import Foundation
import XCTest
@testable import SwiftAtproto

final class SwiftAtprotoTests: XCTestCase {
    func testMakeParameters() throws {
        let items = XRPCBaseClient.makeParameters(params: ["param1[]": ["1", "2", "3"], "param2": "hello"])
        XCTAssertEqual(items.map(\.description).sorted(), ["param1[]=1", "param1[]=2", "param1[]=3", "param2=hello"])
    }
}
