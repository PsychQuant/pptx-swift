import Foundation

/// 主題（對應 theme1.xml）
public struct Theme {
    public var name: String
    public var colorScheme: ColorScheme
    public var fontScheme: FontScheme

    public init(
        name: String = "",
        colorScheme: ColorScheme = ColorScheme(),
        fontScheme: FontScheme = FontScheme()
    ) {
        self.name = name
        self.colorScheme = colorScheme
        self.fontScheme = fontScheme
    }

    /// 解析 scheme color 為 hex RGB
    public func resolveColor(_ schemeName: String) -> String? {
        colorScheme.resolve(schemeName)
    }
}

// MARK: - Color Scheme

/// 色彩配置（12 個命名色彩）
public struct ColorScheme {
    public var name: String = ""
    public var dk1: String = "000000"     // 深色 1
    public var lt1: String = "FFFFFF"     // 淺色 1
    public var dk2: String = "44546A"     // 深色 2
    public var lt2: String = "E7E6E6"     // 淺色 2
    public var accent1: String = "4472C4"
    public var accent2: String = "ED7D31"
    public var accent3: String = "A5A5A5"
    public var accent4: String = "FFC000"
    public var accent5: String = "5B9BD5"
    public var accent6: String = "70AD47"
    public var hlink: String = "0563C1"   // 超連結色
    public var folHlink: String = "954F72" // 已瀏覽超連結色

    public init() {}

    /// 解析 scheme color 名稱為 hex RGB
    public func resolve(_ name: String) -> String? {
        switch name {
        case "dk1": return dk1
        case "lt1": return lt1
        case "dk2": return dk2
        case "lt2": return lt2
        case "accent1": return accent1
        case "accent2": return accent2
        case "accent3": return accent3
        case "accent4": return accent4
        case "accent5": return accent5
        case "accent6": return accent6
        case "hlink": return hlink
        case "folHlink": return folHlink
        case "tx1": return dk1     // text1 = dk1
        case "tx2": return dk2     // text2 = dk2
        case "bg1": return lt1     // background1 = lt1
        case "bg2": return lt2     // background2 = lt2
        default: return nil
        }
    }

    /// 以字典形式回傳所有顏色
    public var allColors: [(name: String, hex: String)] {
        [
            ("dk1", dk1), ("lt1", lt1), ("dk2", dk2), ("lt2", lt2),
            ("accent1", accent1), ("accent2", accent2), ("accent3", accent3),
            ("accent4", accent4), ("accent5", accent5), ("accent6", accent6),
            ("hlink", hlink), ("folHlink", folHlink)
        ]
    }
}

// MARK: - Font Scheme

/// 字型配置
public struct FontScheme {
    public var name: String = ""
    public var majorFont: String = ""  // 標題字型
    public var minorFont: String = ""  // 內文字型

    public init() {}
}
