/// Centimeter and English Metric Unit (EMU) conversions for PPTX geometry.
public enum PPTXMetric {
    /// Converts centimeters to EMU, rounding half away from zero.
    public static func emu(fromCm cm: Double) -> Int {
        Int((cm * 360_000).rounded())
    }

    /// Converts EMU to centimeters using the exact OOXML ratio.
    public static func cm(fromEmu emu: Int) -> Double {
        Double(emu) / 360_000
    }
}

public extension Position {
    var xCm: Double { PPTXMetric.cm(fromEmu: x) }
    var yCm: Double { PPTXMetric.cm(fromEmu: y) }

    init(xCm: Double, yCm: Double) {
        self.init(
            x: PPTXMetric.emu(fromCm: xCm),
            y: PPTXMetric.emu(fromCm: yCm)
        )
    }
}

public extension Size {
    var widthCm: Double { PPTXMetric.cm(fromEmu: width) }
    var heightCm: Double { PPTXMetric.cm(fromEmu: height) }

    init(widthCm: Double, heightCm: Double) {
        self.init(
            width: PPTXMetric.emu(fromCm: widthCm),
            height: PPTXMetric.emu(fromCm: heightCm)
        )
    }
}

public extension SlideSize {
    var widthCm: Double { PPTXMetric.cm(fromEmu: width) }
    var heightCm: Double { PPTXMetric.cm(fromEmu: height) }
}
