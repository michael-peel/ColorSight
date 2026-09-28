import XCTest
@testable import ColorSight

final class ColorMathTests: XCTestCase {

    func testBlackIsZeroLightness() {
        let lab = ColorMath.rgbToLAB(r: 0, g: 0, b: 0)
        XCTAssertEqual(lab.l, 0, accuracy: 0.5)
    }

    func testWhiteIsMaxLightnessAndNeutral() {
        let lab = ColorMath.rgbToLAB(r: 255, g: 255, b: 255)
        XCTAssertEqual(lab.l, 100, accuracy: 0.5)
        XCTAssertEqual(lab.a, 0, accuracy: 0.5)
        XCTAssertEqual(lab.b, 0, accuracy: 0.5)
    }

    func testGrayIsNeutral() {
        let lab = ColorMath.rgbToLAB(r: 128, g: 128, b: 128)
        XCTAssertEqual(lab.a, 0, accuracy: 0.5)
        XCTAssertEqual(lab.b, 0, accuracy: 0.5)
    }

    func testIdenticalColorsHaveZeroDistance() {
        let lab = ColorMath.rgbToLAB(r: 90, g: 160, b: 210)
        XCTAssertEqual(ColorMath.squaredDeltaE(lab, lab), 0, accuracy: 0.0001)
        XCTAssertEqual(ColorMath.deltaE(lab, lab), 0, accuracy: 0.0001)
    }

    func testDeltaEIsSquareRootOfSquaredDeltaE() {
        let a = ColorMath.rgbToLAB(r: 20, g: 40, b: 60)
        let b = ColorMath.rgbToLAB(r: 200, g: 100, b: 30)
        XCTAssertEqual(ColorMath.deltaE(a, b), ColorMath.squaredDeltaE(a, b).squareRoot(), accuracy: 0.0001)
    }

    func testMoreDistantColorsHaveLargerDeltaE() {
        let red        = ColorMath.rgbToLAB(r: 255, g: 0,   b: 0)
        let closeToRed = ColorMath.rgbToLAB(r: 235, g: 20,  b: 10)
        let blue       = ColorMath.rgbToLAB(r: 0,   g: 0,   b: 255)
        XCTAssertLessThan(
            ColorMath.deltaE(red, closeToRed),
            ColorMath.deltaE(red, blue)
        )
    }
}
