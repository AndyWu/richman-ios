import XCTest
@testable import RichmanPersistence

final class RichmanPersistenceTests: XCTestCase {
    func testModuleNameIsSet() {
        XCTAssertEqual(RichmanPersistence.moduleName, "RichmanPersistence")
    }
}
