import Testing
import Foundation
@testable import PPTXSwift

/// Boundary behaviour of the cm ↔ EMU conversions (PsychQuant/macdoc#90 review,
/// HIGH 1 / MEDIUM 4): the supported range is the OOXML `ST_Coordinate` range,
/// unsupported input throws instead of trapping, rounding is half away from
/// zero on the exact 360,000 ratio, and every EMU in range round-trips exactly.
struct MetricConversionBoundaryTests {

    static let maxEmu = PPTXMetric.maxCoordinateEmu
    static let minEmu = PPTXMetric.minCoordinateEmu

    // MARK: - Supported range

    @Test func `Supported range is the OOXML ST_Coordinate range`() {
        #expect(PPTXMetric.minCoordinateEmu == -27_273_042_329_600)
        #expect(PPTXMetric.maxCoordinateEmu == 27_273_042_316_900)
        #expect(PPTXMetric.coordinateRangeEmu == -27_273_042_329_600...27_273_042_316_900)
    }

    // MARK: - Unsupported input throws, never traps

    static let unsupportedCm: [Double] = [
        .nan, -.nan, .signalingNaN,
        .infinity, -.infinity,
        .greatestFiniteMagnitude, -.greatestFiniteMagnitude,
        1e300, -1e300,
        PPTXMetric.cm(fromEmu: maxEmu + 1), PPTXMetric.cm(fromEmu: minEmu - 1),
        PPTXMetric.cm(fromEmu: Int.max), PPTXMetric.cm(fromEmu: Int.min),
    ]

    @Test(arguments: unsupportedCm)
    func `Unsupported cm values throw from every cm-denominated API`(cm: Double) {
        #expect(throws: PPTXError.self) { _ = try PPTXMetric.emu(fromCm: cm) }
        #expect(throws: PPTXError.self) { _ = try Position(xCm: cm, yCm: 0) }
        #expect(throws: PPTXError.self) { _ = try Position(xCm: 0, yCm: cm) }
        #expect(throws: PPTXError.self) { _ = try Size(widthCm: cm, heightCm: 1) }
        #expect(throws: PPTXError.self) { _ = try Size(widthCm: 1, heightCm: cm) }
    }

    @Test func `Int.max EMU does not trap on the way back`() {
        #expect(throws: PPTXError.self) {
            _ = try PPTXMetric.emu(fromCm: PPTXMetric.cm(fromEmu: Int.max))
        }
    }

    // MARK: - Range endpoints

    @Test func `Range endpoints convert exactly through every cm API`() throws {
        let maxCm = PPTXMetric.cm(fromEmu: Self.maxEmu)
        let minCm = PPTXMetric.cm(fromEmu: Self.minEmu)
        #expect(try PPTXMetric.emu(fromCm: maxCm) == Self.maxEmu)
        #expect(try PPTXMetric.emu(fromCm: minCm) == Self.minEmu)

        let position = try Position(xCm: maxCm, yCm: minCm)
        #expect(position.x == Self.maxEmu && position.y == Self.minEmu)
        let size = try Size(widthCm: maxCm, heightCm: maxCm)
        #expect(size.width == Self.maxEmu && size.height == Self.maxEmu)
    }

    @Test func `Within half an EMU of an endpoint rounds inside, beyond it is rejected`() throws {
        let justInsideMax = (Double(Self.maxEmu) + 0.25) / 360_000
        let justOutsideMax = (Double(Self.maxEmu) + 0.75) / 360_000
        #expect(try PPTXMetric.emu(fromCm: justInsideMax) == Self.maxEmu)
        #expect(throws: PPTXError.self) { _ = try PPTXMetric.emu(fromCm: justOutsideMax) }

        let justInsideMin = (Double(Self.minEmu) - 0.25) / 360_000
        let justOutsideMin = (Double(Self.minEmu) - 0.75) / 360_000
        #expect(try PPTXMetric.emu(fromCm: justInsideMin) == Self.minEmu)
        #expect(throws: PPTXError.self) { _ = try PPTXMetric.emu(fromCm: justOutsideMin) }
    }

    // MARK: - Exact per-EMU round trip

    static let endpointEmus: [Int] = [
        minEmu, minEmu + 1, minEmu + 2,
        -360_001, -360_000, -359_999, -1, 0, 1, 359_999, 360_000, 360_001,
        maxEmu - 2, maxEmu - 1, maxEmu,
    ]

    @Test(arguments: endpointEmus)
    func `EMU at and near the endpoints round-trips exactly`(emu: Int) throws {
        #expect(try PPTXMetric.emu(fromCm: PPTXMetric.cm(fromEmu: emu)) == emu)
    }

    @Test func `Every EMU in dense sweeps round-trips exactly`() throws {
        let sweeps: [ClosedRange<Int>] = [
            -200_000...200_000,
            (Self.maxEmu - 100_000)...Self.maxEmu,
            Self.minEmu...(Self.minEmu + 100_000),
        ]
        var mismatches: [Int] = []
        for sweep in sweeps {
            for emu in sweep {
                if try PPTXMetric.emu(fromCm: PPTXMetric.cm(fromEmu: emu)) != emu {
                    mismatches.append(emu)
                }
            }
        }
        #expect(mismatches.isEmpty, "first mismatches: \(mismatches.prefix(5))")
    }

    // MARK: - ±0.5 EMU boundaries (half away from zero)

    /// 1/128 cm × 360,000 = 2812.5 EMU and 3/128 cm = 8437.5 EMU, both exact
    /// in binary floating point, so these are true half-EMU ties.
    static let halfEmuTies: [(cm: Double, tieEmu: Double)] = [
        (1.0 / 128.0, 2812.5),
        (3.0 / 128.0, 8437.5),
        (125.0 / 128.0, 351_562.5),
    ]

    @Test(arguments: halfEmuTies)
    func `Half-EMU ties round away from zero and neighbours round to nearest`(
        tie: (cm: Double, tieEmu: Double)
    ) throws {
        #expect(tie.cm * 360_000 == tie.tieEmu, "tie must be exact for the test to mean anything")
        let up = Int(tie.tieEmu.rounded(.up))
        let down = Int(tie.tieEmu.rounded(.down))

        #expect(try PPTXMetric.emu(fromCm: tie.cm) == up)
        #expect(try PPTXMetric.emu(fromCm: -tie.cm) == -up)
        #expect(try PPTXMetric.emu(fromCm: tie.cm.nextDown) == down)
        #expect(try PPTXMetric.emu(fromCm: tie.cm.nextUp) == up)
        #expect(try PPTXMetric.emu(fromCm: (-tie.cm).nextUp) == -down)
        #expect(try PPTXMetric.emu(fromCm: (-tie.cm).nextDown) == -up)
    }

    @Test func `Negative zero converts to zero`() throws {
        #expect(try PPTXMetric.emu(fromCm: -0.0) == 0)
    }
}
