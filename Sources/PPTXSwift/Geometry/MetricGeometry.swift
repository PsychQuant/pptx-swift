/// Centimeter and English Metric Unit (EMU) conversions for PPTX geometry.
///
/// **Supported range.** EMU values are OOXML `ST_Coordinate` values
/// (ECMA-376 Part 1, §20.1.10.16): `minCoordinateEmu ... maxCoordinateEmu`,
/// about ±75,758 km. Every conversion *into* EMU is validated against that
/// range and **throws** `PPTXError.invalidParameter` for non-finite input or a
/// result outside it — it never traps. The conversion *out of* EMU,
/// `cm(fromEmu:)`, is total: it accepts any `Int` and cannot fail.
///
/// **Exactness.** The ratio is exactly 360,000 EMU per cm and cm → EMU rounds
/// half away from zero. For every EMU `e` in the supported range,
/// `try emu(fromCm: cm(fromEmu: e)) == e` holds exactly.
public enum PPTXMetric {
    /// EMU per centimeter (exact).
    public static let emuPerCm = 360_000

    /// Smallest `ST_Coordinate` value, in EMU.
    public static let minCoordinateEmu = -27_273_042_329_600

    /// Largest `ST_Coordinate` (and `ST_PositiveCoordinate`) value, in EMU.
    public static let maxCoordinateEmu = 27_273_042_316_900

    /// The supported EMU range for every cm → EMU conversion.
    public static let coordinateRangeEmu = minCoordinateEmu...maxCoordinateEmu

    /// Converts centimeters to EMU, rounding half away from zero.
    ///
    /// - Throws: `PPTXError.invalidParameter` when `cm` is NaN or infinite, or
    ///   when the rounded EMU value falls outside `coordinateRangeEmu`.
    public static func emu(fromCm cm: Double) throws -> Int {
        try emu(fromCm: cm, parameter: "cm")
    }

    /// Converts EMU to centimeters using the exact ratio. Total: never throws
    /// or traps (values beyond the supported range are converted too, but
    /// `emu(fromCm:)` will reject them on the way back).
    public static func cm(fromEmu emu: Int) -> Double {
        Double(emu) / Double(emuPerCm)
    }

    /// `emu(fromCm:)` with the caller's parameter name in the error.
    static func emu(fromCm cm: Double, parameter: String) throws -> Int {
        guard cm.isFinite else {
            throw PPTXError.invalidParameter(parameter, "必須是有限數值（收到 \(cm)）")
        }
        // Validate the rounded value as a Double *before* converting to Int,
        // so no input can reach a trapping Int(_:) conversion. Both bounds are
        // exactly representable (|bound| < 2^53).
        let rounded = (cm * Double(emuPerCm)).rounded(.toNearestOrAwayFromZero)
        guard rounded >= Double(minCoordinateEmu), rounded <= Double(maxCoordinateEmu) else {
            throw PPTXError.invalidParameter(
                parameter,
                "超出 OOXML 座標範圍（收到 \(cm) cm；支援 \(Self.cm(fromEmu: minCoordinateEmu)) … \(Self.cm(fromEmu: maxCoordinateEmu)) cm）"
            )
        }
        return Int(rounded)
    }
}

public extension Position {
    var xCm: Double { PPTXMetric.cm(fromEmu: x) }
    var yCm: Double { PPTXMetric.cm(fromEmu: y) }

    /// Creates a position from centimeters.
    /// - Throws: `PPTXError.invalidParameter` for non-finite or out-of-range values.
    init(xCm: Double, yCm: Double) throws {
        self.init(
            x: try PPTXMetric.emu(fromCm: xCm, parameter: "xCm"),
            y: try PPTXMetric.emu(fromCm: yCm, parameter: "yCm")
        )
    }
}

public extension Size {
    var widthCm: Double { PPTXMetric.cm(fromEmu: width) }
    var heightCm: Double { PPTXMetric.cm(fromEmu: height) }

    /// Creates a size from centimeters. Only the supported range is checked
    /// here; positivity of an extent is enforced by `PPTXMetric.geometry`.
    /// - Throws: `PPTXError.invalidParameter` for non-finite or out-of-range values.
    init(widthCm: Double, heightCm: Double) throws {
        self.init(
            width: try PPTXMetric.emu(fromCm: widthCm, parameter: "widthCm"),
            height: try PPTXMetric.emu(fromCm: heightCm, parameter: "heightCm")
        )
    }
}

public extension SlideSize {
    var widthCm: Double { PPTXMetric.cm(fromEmu: width) }
    var heightCm: Double { PPTXMetric.cm(fromEmu: height) }
}
