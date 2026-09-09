import XCTest
@testable import RichmanCore

final class RichmanCoreTests: XCTestCase {
    func testModuleNameIsSet() {
        XCTAssertEqual(RichmanCore.moduleName, "RichmanCore")
    }
}
