import XCTest
@testable import ColorSight

final class IsolationTargetTests: XCTestCase {

    // MARK: - family case delegates to HueFamily.matches()

    func testFamilyCaseMatchesDelegatesToHueFamily() {
        let target = IsolationTarget.family(.red)
        XCTAssertTrue(target.matches(r: 255, g: 0, b: 0))
        XCTAssertFalse(target.matches(r: 0, g: 200, b: 0))
    }

    // MARK: - custom case: LAB distance vs tolerance

    func testCustomCaseMatchesExactColor() {
        let target = IsolationTarget.custom(r: 100, g: 150, b: 200, tolerance: 15)
        XCTAssertTrue(target.matches(r: 100, g: 150, b: 200))
    }

    func testCustomCaseMatchesWithinTolerance() {
        // A slightly different but perceptually close color should still match.
        let target = IsolationTarget.custom(r: 100, g: 150, b: 200, tolerance: 15)
        XCTAssertTrue(target.matches(r: 105, g: 152, b: 198))
    }

    func testCustomCaseRejectsBeyondTolerance() {
        let target = IsolationTarget.custom(r: 100, g: 150, b: 200, tolerance: 15)
        XCTAssertFalse(target.matches(r: 255, g: 0, b: 0))
    }

    func testTighterToleranceRejectsWhatLooserToleranceAccepts() {
        // ΔE between (100,150,200) and (70,110,160) is ~15.4 — verified against the
        // same sRGB→LAB pipeline offline, not guessed. Deliberately straddles the two
        // tolerances below.
        let nearbyColor = (r: 70, g: 110, b: 160)
        let strict = IsolationTarget.custom(r: 100, g: 150, b: 200, tolerance: 10)
        let loose  = IsolationTarget.custom(r: 100, g: 150, b: 200, tolerance: 20)

        XCTAssertFalse(strict.matches(r: nearbyColor.r, g: nearbyColor.g, b: nearbyColor.b))
        XCTAssertTrue(loose.matches(r: nearbyColor.r, g: nearbyColor.g, b: nearbyColor.b))
    }

    // MARK: - Display properties

    func testDisplayNameAndSwatchColor() {
        XCTAssertEqual(IsolationTarget.family(.blue).displayName, "Blue")
        XCTAssertEqual(IsolationTarget.custom(r: 1, g: 2, b: 3, tolerance: 15).displayName, "Custom")
    }
}
