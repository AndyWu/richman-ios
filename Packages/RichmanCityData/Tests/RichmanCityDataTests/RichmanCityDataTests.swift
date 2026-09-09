import XCTest
@testable import RichmanCityData

final class RichmanCityDataTests: XCTestCase {
    func testModuleNameIsSet() {
        XCTAssertEqual(RichmanCityData.moduleName, "RichmanCityData")
    }
}
