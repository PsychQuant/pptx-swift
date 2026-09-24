import XCTest
@testable import PPTXSwift

/// §1.1–§1.2 — cm↔EMU conversion + centimeter accessors.
///
/// Covers spec `pptx-metric-geometry` Requirements:
///   - "Centimeter-EMU conversion is exact-ratio and round-trip stable"
///   - "Existing geometry types gain centimeter accessors"
final class MetricGeometryTests: XCTestCase {

    // MARK: - Worked conversions (spec ##### Example: Worked conversions)

    func testWorkedConversionsCmToEmu() {
        // 1 cm = exactly 360_000 EMU.
        XCTAssertEqual(try PPTXMetric.emu(fromCm: 2.0), 720000)
        XCTAssertEqual(try PPTXMetric.emu(fromCm: 3.0), 1080000)
        XCTAssertEqual(try PPTXMetric.emu(fromCm: 10.0), 3600000)
        XCTAssertEqual(try PPTXMetric.emu(fromCm: 2.54), 914400)
    }

    func testWorkedConversionsEmuToCm() {
        XCTAssertEqual(PPTXMetric.cm(fromEmu: 9144000), 25.4, accuracy: 1e-9)
        XCTAssertEqual(PPTXMetric.cm(fromEmu: 6858000), 19.05, accuracy: 1e-9)
    }

    // MARK: - Round-trip stability (spec Scenario: Round-trip stability)

    func testRoundTripStability() throws {
        // Each input is a whole number of EMU, so both directions are exact:
        // the recovered cm equals the input, and it converts back to the same EMU.
        for x in [0.0, 0.01, 2.54, 33.33, 100.0] {
            let emu = try PPTXMetric.emu(fromCm: x)
            let recovered = PPTXMetric.cm(fromEmu: emu)
            XCTAssertEqual(recovered, x, "round-trip for \(x) cm drifted to \(recovered)")
            XCTAssertEqual(try PPTXMetric.emu(fromCm: recovered), emu, "EMU round-trip for \(x) cm")
        }
    }

    func testOffGridRoundTripIsExactInEMUAndWithinHalfAnEMUInCm() throws {
        // Not whole EMU: the cm value cannot survive exactly, but the EMU value
        // must, and the cm error is bounded by rounding (half an EMU).
        for x in [1.2345678, 0.0000001, 33.333333, 99.9999999, -7.7777777] {
            let emu = try PPTXMetric.emu(fromCm: x)
            let recovered = PPTXMetric.cm(fromEmu: emu)
            XCTAssertEqual(try PPTXMetric.emu(fromCm: recovered), emu, "EMU round-trip for \(x) cm")
            XCTAssertLessThanOrEqual(abs(recovered - x), 0.5 / 360_000 + 1e-12, "\(x) cm")
        }
    }

    // MARK: - Default slide dimensions in cm (spec Scenario)

    func testDefaultSlideDimensionsInCm() {
        let slide = SlideSize()  // default 9144000 x 6858000 EMU
        XCTAssertEqual(slide.widthCm, 25.4, accuracy: 1e-9)
        XCTAssertEqual(slide.heightCm, 19.05, accuracy: 1e-9)
    }

    // MARK: - Centimeter-denominated construction (spec Scenario)

    func testPositionCmConstruction() throws {
        let pos = try Position(xCm: 2.0, yCm: 3.0)
        XCTAssertEqual(pos.x, 720000)
        XCTAssertEqual(pos.y, 1080000)
    }

    func testSizeCmConstruction() throws {
        let size = try Size(widthCm: 10.0, heightCm: 7.5)
        XCTAssertEqual(size.width, 3600000)
        XCTAssertEqual(size.height, 2700000)
    }

    // MARK: - Centimeter getters

    func testPositionCmGetters() {
        let pos = Position(x: 720000, y: 1080000)
        XCTAssertEqual(pos.xCm, 2.0, accuracy: 1e-9)
        XCTAssertEqual(pos.yCm, 3.0, accuracy: 1e-9)
    }

    func testSizeCmGetters() {
        let size = Size(width: 3600000, height: 2700000)
        XCTAssertEqual(size.widthCm, 10.0, accuracy: 1e-9)
        XCTAssertEqual(size.heightCm, 7.5, accuracy: 1e-9)
    }
}
