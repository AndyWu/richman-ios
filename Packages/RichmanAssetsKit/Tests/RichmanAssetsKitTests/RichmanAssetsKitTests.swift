import XCTest
@testable import RichmanAssetsKit

final class RichmanAssetsKitTests: XCTestCase {
    func testModuleNameIsSet() {
        XCTAssertEqual(RichmanAssetsKit.moduleName, "RichmanAssetsKit")
    }
}
