import XCTest
@testable import ColorSight

final class WhiteBalanceCalibrationTests: XCTestCase {

    private let neutralGains = WhiteBalanceCalibration.Gains(red: 1.0, green: 1.0, blue: 1.0)

    func testNeutralGraySampleNeedsNoCorrection() {
        let gains = WhiteBalanceCalibration.correctedGains(
            measuredR: 180, measuredG: 180, measuredB: 180,
            currentGains: neutralGains, maxGain: 4.0
        )
        XCTAssertNotNil(gains)
        XCTAssertEqual(gains!.red,   1.0, accuracy: 0.001)
        XCTAssertEqual(gains!.green, 1.0, accuracy: 0.001)
        XCTAssertEqual(gains!.blue,  1.0, accuracy: 0.001)
    }

    func testWarmCastBoostsBlueGain() {
        // A "white" surface reading warm (too much red, not enough blue) should get a
        // corrective boost to blue gain. Gains can never go below 1.0 (Apple's API
        // floor), so starting from neutral (1,1,1) gains, red just clamps at 1.0
        // rather than actually decreasing — the correction is entirely a blue boost.
        let gains = WhiteBalanceCalibration.correctedGains(
            measuredR: 220, measuredG: 180, measuredB: 120,
            currentGains: neutralGains, maxGain: 4.0
        )
        XCTAssertNotNil(gains)
        XCTAssertEqual(gains!.red, 1.0, accuracy: 0.001)
        XCTAssertGreaterThan(gains!.blue, 1.0)
    }

    func testCoolCastBoostsRedGain() {
        // Same floor-at-1.0 reasoning as the warm-cast case above, mirrored: blue
        // clamps at 1.0, red gets the corrective boost.
        let gains = WhiteBalanceCalibration.correctedGains(
            measuredR: 120, measuredG: 180, measuredB: 220,
            currentGains: neutralGains, maxGain: 4.0
        )
        XCTAssertNotNil(gains)
        XCTAssertGreaterThan(gains!.red, 1.0)
        XCTAssertEqual(gains!.blue, 1.0, accuracy: 0.001)
    }

    func testGainsClampToMaxGain() {
        let gains = WhiteBalanceCalibration.correctedGains(
            measuredR: 250, measuredG: 250, measuredB: 15,
            currentGains: neutralGains, maxGain: 2.0
        )
        XCTAssertNotNil(gains)
        XCTAssertEqual(gains!.blue, 2.0, accuracy: 0.001)
    }

    func testGainsNeverGoBelowOne() {
        let gains = WhiteBalanceCalibration.correctedGains(
            measuredR: 250, measuredG: 100, measuredB: 100,
            currentGains: neutralGains, maxGain: 4.0
        )
        XCTAssertNotNil(gains)
        XCTAssertEqual(gains!.red, 1.0, accuracy: 0.001)
    }

    func testCompoundsWithExistingCurrentGains() {
        let existing = WhiteBalanceCalibration.Gains(red: 1.5, green: 1.0, blue: 1.2)
        let gains = WhiteBalanceCalibration.correctedGains(
            measuredR: 180, measuredG: 180, measuredB: 180,
            currentGains: existing, maxGain: 4.0
        )
        // A neutral sample under the CURRENT gains needs no further correction —
        // output should equal the input gains unchanged.
        XCTAssertNotNil(gains)
        XCTAssertEqual(gains!.red,   1.5, accuracy: 0.001)
        XCTAssertEqual(gains!.green, 1.0, accuracy: 0.001)
        XCTAssertEqual(gains!.blue,  1.2, accuracy: 0.001)
    }

    func testTooDarkSampleReturnsNil() {
        let gains = WhiteBalanceCalibration.correctedGains(
            measuredR: 5, measuredG: 4, measuredB: 6,
            currentGains: neutralGains, maxGain: 4.0
        )
        XCTAssertNil(gains)
    }
}
