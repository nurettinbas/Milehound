import XCTest
@testable import Milehound

final class VehicleIconOptionTests: XCTestCase {
    func testDefaultIsRightFacingCarSide() {
        XCTAssertEqual(VehicleIconOption.default, .carSide)
        XCTAssertEqual(VehicleIconOption.default.rawValue, "car.side.fill")
    }

    func testResolvedUnknownFallsBackToDefault() {
        XCTAssertEqual(VehicleIconOption.resolved(nil), .default)
        XCTAssertEqual(VehicleIconOption.resolved("not.a.real.symbol"), .default)
        XCTAssertEqual(VehicleIconOption.resolved("fuelpump.fill"), .default)
    }

    func testResolvedKnownOption() {
        XCTAssertEqual(VehicleIconOption.resolved("suv.side.fill"), .suv)
    }
}
