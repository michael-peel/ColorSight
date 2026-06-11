import XCTest
@testable import ColorSight

final class HueFamilyTests: XCTestCase {

    // MARK: - metalIndex

    // metalIndex must mirror the case order in the Metal shader's matchesFamily() switch.
    // If these offsets drift, the GPU and CPU classification paths disagree silently.
    func testMetalIndexMatchesCaseOrder() {
        XCTAssertEqual(HueFamily.red.metalIndex,    0)
        XCTAssertEqual(HueFamily.orange.metalIndex, 1)
        XCTAssertEqual(HueFamily.yellow.metalIndex, 2)
        XCTAssertEqual(HueFamily.green.metalIndex,  3)
        XCTAssertEqual(HueFamily.blue.metalIndex,   4)
        XCTAssertEqual(HueFamily.purple.metalIndex, 5)
        XCTAssertEqual(HueFamily.pink.metalIndex,   6)
        XCTAssertEqual(HueFamily.brown.metalIndex,  7)
        XCTAssertEqual(HueFamily.white.metalIndex,  8)
        XCTAssertEqual(HueFamily.gray.metalIndex,   9)
        XCTAssertEqual(HueFamily.black.metalIndex,  10)
    }

    // MARK: - Canonical chromatic colors

    func testPureRedMatchesOnlyRed() {
        XCTAssertTrue(HueFamily.red.matches(r: 255, g: 0, b: 0))
        XCTAssertFalse(HueFamily.orange.matches(r: 255, g: 0, b: 0))
        XCTAssertFalse(HueFamily.pink.matches(r: 255, g: 0, b: 0))
        XCTAssertFalse(HueFamily.green.matches(r: 255, g: 0, b: 0))
    }

    func testPureGreenMatchesGreen() {
        XCTAssertTrue(HueFamily.green.matches(r: 0, g: 200, b: 0))
        XCTAssertFalse(HueFamily.red.matches(r: 0, g: 200, b: 0))
        XCTAssertFalse(HueFamily.yellow.matches(r: 0, g: 200, b: 0))
    }

    func testPureBlueMatchesBlue() {
        XCTAssertTrue(HueFamily.blue.matches(r: 0, g: 0, b: 255))
        XCTAssertFalse(HueFamily.purple.matches(r: 0, g: 0, b: 255))
        XCTAssertFalse(HueFamily.green.matches(r: 0, g: 0, b: 255))
    }

    func testCanonicalOrangeMatchesOrange() {
        // RGB(255,140,0) — hue ≈ 33°, saturation 1.0, brightness 1.0
        XCTAssertTrue(HueFamily.orange.matches(r: 255, g: 140, b: 0))
        XCTAssertFalse(HueFamily.red.matches(r: 255, g: 140, b: 0))
        XCTAssertFalse(HueFamily.brown.matches(r: 255, g: 140, b: 0))
        XCTAssertFalse(HueFamily.yellow.matches(r: 255, g: 140, b: 0))
    }

    func testCanonicalYellowMatchesYellow() {
        // RGB(255,220,0) — hue ≈ 52°
        XCTAssertTrue(HueFamily.yellow.matches(r: 255, g: 220, b: 0))
        XCTAssertFalse(HueFamily.orange.matches(r: 255, g: 220, b: 0))
        XCTAssertFalse(HueFamily.green.matches(r: 255, g: 220, b: 0))
    }

    func testPurpleMatchesPurple() {
        // RGB(128,0,200) — hue ≈ 277°
        XCTAssertTrue(HueFamily.purple.matches(r: 128, g: 0, b: 200))
        XCTAssertFalse(HueFamily.blue.matches(r: 128, g: 0, b: 200))
        XCTAssertFalse(HueFamily.pink.matches(r: 128, g: 0, b: 200))
    }

    func testHotPinkMatchesPink() {
        // RGB(255,105,180) — hue ≈ 330°
        XCTAssertTrue(HueFamily.pink.matches(r: 255, g: 105, b: 180))
        XCTAssertFalse(HueFamily.red.matches(r: 255, g: 105, b: 180))
        XCTAssertFalse(HueFamily.purple.matches(r: 255, g: 105, b: 180))
    }

    func testChocolateBrownMatchesBrown() {
        // RGB(101,67,33) — hue ≈ 30°, low brightness
        XCTAssertTrue(HueFamily.brown.matches(r: 101, g: 67, b: 33))
        XCTAssertFalse(HueFamily.orange.matches(r: 101, g: 67, b: 33))
        XCTAssertFalse(HueFamily.red.matches(r: 101, g: 67, b: 33))
    }

    // MARK: - Achromatic families

    func testWhiteMatchesWhiteOnly() {
        XCTAssertTrue(HueFamily.white.matches(r: 255, g: 255, b: 255))
        XCTAssertFalse(HueFamily.gray.matches(r: 255, g: 255, b: 255))
        XCTAssertFalse(HueFamily.black.matches(r: 255, g: 255, b: 255))
    }

    func testMidGrayMatchesGrayOnly() {
        XCTAssertTrue(HueFamily.gray.matches(r: 128, g: 128, b: 128))
        XCTAssertFalse(HueFamily.white.matches(r: 128, g: 128, b: 128))
        XCTAssertFalse(HueFamily.black.matches(r: 128, g: 128, b: 128))
    }

    func testBlackMatchesBlackOnly() {
        XCTAssertTrue(HueFamily.black.matches(r: 0, g: 0, b: 0))
        XCTAssertFalse(HueFamily.gray.matches(r: 0, g: 0, b: 0))
        XCTAssertFalse(HueFamily.white.matches(r: 0, g: 0, b: 0))
    }

    // MARK: - Chromatic families reject achromatic pixels

    func testRedDoesNotMatchGray() {
        XCTAssertFalse(HueFamily.red.matches(r: 128, g: 128, b: 128))
    }

    func testBlueDoesNotMatchWhite() {
        XCTAssertFalse(HueFamily.blue.matches(r: 250, g: 250, b: 250))
    }

    func testGreenDoesNotMatchBlack() {
        XCTAssertFalse(HueFamily.green.matches(r: 10, g: 10, b: 10))
    }

    // MARK: - Red wraps at 0°/360°

    func testDeepRoseNear360IsRed() {
        // RGB(220,20,60) — hue ≈ 348°, right of the 345° red boundary
        XCTAssertTrue(HueFamily.red.matches(r: 220, g: 20, b: 60))
        XCTAssertFalse(HueFamily.pink.matches(r: 220, g: 20, b: 60))
    }

    // MARK: - Orange / brown brightness boundary

    func testBrightOrangeHueBandIsOrange() {
        // Hue ≈ 25°, brightness > 0.45 → orange
        XCTAssertTrue(HueFamily.orange.matches(r: 200, g: 100, b: 20))
        XCTAssertFalse(HueFamily.brown.matches(r: 200, g: 100, b: 20))
    }

    func testDarkOrangeHueBandIsBrown() {
        // Same hue band, brightness < 0.45 → brown
        XCTAssertTrue(HueFamily.brown.matches(r: 100, g: 50, b: 10))
        XCTAssertFalse(HueFamily.orange.matches(r: 100, g: 50, b: 10))
    }
}
