import XCTest
@testable import ColorSight

final class ColorEngineTests: XCTestCase {

    private let engine = ColorEngine()

    // MARK: - Hex format

    func testHexIsSevenCharsPrefixedWithHash() {
        let color = engine.identify(r: 135, g: 206, b: 235)
        XCTAssertTrue(color.hex.hasPrefix("#"), "hex must start with #")
        XCTAssertEqual(color.hex.count, 7,       "hex must be 7 chars: #RRGGBB")
        XCTAssertEqual(color.hex, "#87CEEB")
    }

    func testHexIsUppercase() {
        let color = engine.identify(r: 171, g: 205, b: 239)  // #ABCDEF
        XCTAssertEqual(color.hex, "#ABCDEF")
    }

    // MARK: - RGB round-trip

    func testRGBComponentsMatchInput() {
        let r: UInt8 = 123, g: UInt8 = 45, b: UInt8 = 67
        let color = engine.identify(r: r, g: g, b: b)
        XCTAssertEqual(color.rgb.r, Int(r))
        XCTAssertEqual(color.rgb.g, Int(g))
        XCTAssertEqual(color.rgb.b, Int(b))
    }

    // MARK: - HSL ranges

    func testHSLComponentsAreInValidRanges() {
        let color = engine.identify(r: 255, g: 100, b: 0)
        XCTAssertGreaterThanOrEqual(color.hsl.h, 0)
        XCTAssertLessThan(color.hsl.h, 360)
        XCTAssertGreaterThanOrEqual(color.hsl.s, 0)
        XCTAssertLessThanOrEqual(color.hsl.s, 1)
        XCTAssertGreaterThanOrEqual(color.hsl.l, 0)
        XCTAssertLessThanOrEqual(color.hsl.l, 1)
    }

    func testPureBlackHasZeroHSL() {
        let color = engine.identify(r: 0, g: 0, b: 0)
        XCTAssertEqual(color.hsl.s, 0, accuracy: 0.001)
        XCTAssertEqual(color.hsl.l, 0, accuracy: 0.001)
    }

    func testPureWhiteHasMaxLightness() {
        let color = engine.identify(r: 255, g: 255, b: 255)
        XCTAssertEqual(color.hsl.s, 0, accuracy: 0.001)
        XCTAssertEqual(color.hsl.l, 1, accuracy: 0.001)
    }

    // MARK: - simpleName plausibility

    func testVividRedReturnsRedName() {
        let color = engine.identify(r: 220, g: 20, b: 20)
        XCTAssertTrue(
            color.simpleName.lowercased().contains("red"),
            "Expected a red simple name, got '\(color.simpleName)'"
        )
    }

    func testVividBlueReturnsBlueName() {
        let color = engine.identify(r: 0, g: 80, b: 220)
        XCTAssertTrue(
            color.simpleName.lowercased().contains("blue"),
            "Expected a blue simple name, got '\(color.simpleName)'"
        )
    }

    func testBlackReturnsBlackName() {
        let color = engine.identify(r: 0, g: 0, b: 0)
        XCTAssertTrue(
            color.simpleName.lowercased().contains("black"),
            "Expected black, got '\(color.simpleName)'"
        )
    }

    func testWhiteReturnsWhiteName() {
        let color = engine.identify(r: 255, g: 255, b: 255)
        XCTAssertTrue(
            color.simpleName.lowercased().contains("white"),
            "Expected white, got '\(color.simpleName)'"
        )
    }

    // MARK: - CVD description

    func testCVDDescriptionIsNonEmptyForAllProfiles() {
        for profile in CVDProfile.allCases {
            let color = engine.identify(r: 100, g: 150, b: 200, profile: profile)
            XCTAssertFalse(
                color.cvdDescription.isEmpty,
                "CVD description empty for profile \(profile.rawValue)"
            )
        }
    }

    func testAchromatopsiaMentionsBrightness() {
        let color = engine.identify(r: 100, g: 150, b: 200, profile: .achromatopsia)
        XCTAssertTrue(
            color.cvdDescription.lowercased().contains("bright") ||
            color.cvdDescription.lowercased().contains("grey") ||
            color.cvdDescription.lowercased().contains("gray"),
            "Achromatopsia description should mention brightness/grey, got '\(color.cvdDescription)'"
        )
    }
}
