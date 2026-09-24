import Foundation

/// 形狀（文字框、矩形、橢圓等）
public struct Shape {
    public var id: Int
    public var name: String
    public var placeholder: PlaceholderType?
    public var geometry: ShapeGeometry
    public var position: Position
    public var size: Size
    /// 旋轉角度（`a:xfrm` 的 `rot`，ECMA-376 `ST_Angle`：以 60,000 分之一度為單位的
    /// 整數，順時針為正）。`ST_Angle` 是不限範圍的 `xsd:int`（見 `PptxWriter` 正規化
    /// 說明），讀取時原樣保留；0（schema 預設）表示未旋轉，寫出時省略 `rot` 屬性。
    public var rotation: Int
    /// 是否沿垂直軸水平翻轉（`a:xfrm` 的 `flipH`）。
    public var flipHorizontal: Bool
    /// 是否沿水平軸垂直翻轉（`a:xfrm` 的 `flipV`）。
    public var flipVertical: Bool
    public var fill: ShapeFill?
    public var outline: ShapeOutline?
    public var textBody: TextBody?

    public init(
        id: Int = 0,
        name: String = "",
        placeholder: PlaceholderType? = nil,
        geometry: ShapeGeometry = .rect,
        position: Position = Position(),
        size: Size = Size(),
        rotation: Int = 0,
        flipHorizontal: Bool = false,
        flipVertical: Bool = false,
        fill: ShapeFill? = nil,
        outline: ShapeOutline? = nil,
        textBody: TextBody? = nil
    ) {
        self.id = id
        self.name = name
        self.placeholder = placeholder
        self.geometry = geometry
        self.position = position
        self.size = size
        self.rotation = rotation
        self.flipHorizontal = flipHorizontal
        self.flipVertical = flipVertical
        self.fill = fill
        self.outline = outline
        self.textBody = textBody
    }
}

// MARK: - Placeholder Type

/// 佔位符類型
public enum PlaceholderType: String {
    case title = "title"
    case centerTitle = "ctrTitle"
    case subtitle = "subTitle"
    case body = "body"
    case dateTime = "dt"
    case footer = "ftr"
    case slideNumber = "sldNum"
    case object = "obj"
    case chart = "chart"
    case table = "tbl"
    case clipArt = "clipArt"
    case diagram = "dgm"
    case media = "media"
    case picture = "pic"
    case header = "hdr"
    case unknown
}

// MARK: - Shape Geometry

/// 預設幾何形狀
public enum ShapeGeometry: String {
    case rect
    case ellipse
    case roundRect
    case triangle = "triangle"
    case diamond
    case pentagon
    case hexagon
    case rightArrow
    case leftArrow
    case upArrow
    case downArrow
    case star5 = "star5"
    case line
    case custom
    case unknown
}

// MARK: - Position & Size (EMU)

/// 位置（EMU 單位，1 inch = 914400 EMU）
public struct Position {
    public var x: Int  // EMU
    public var y: Int  // EMU

    public init(x: Int = 0, y: Int = 0) {
        self.x = x
        self.y = y
    }

    public var xInches: Double { Double(x) / 914400.0 }
    public var yInches: Double { Double(y) / 914400.0 }
    public var xPoints: Double { Double(x) / 12700.0 }
    public var yPoints: Double { Double(y) / 12700.0 }
}

/// 大小（EMU 單位）
public struct Size {
    public var width: Int   // cx, EMU
    public var height: Int  // cy, EMU

    public init(width: Int = 0, height: Int = 0) {
        self.width = width
        self.height = height
    }

    public var widthInches: Double { Double(width) / 914400.0 }
    public var heightInches: Double { Double(height) / 914400.0 }
    public var widthPoints: Double { Double(width) / 12700.0 }
    public var heightPoints: Double { Double(height) / 12700.0 }
}

// MARK: - Shape Fill

/// 形狀填色
public enum ShapeFill {
    case solid(color: String)           // hex RGB e.g. "FF0000"
    case schemeColor(name: String)      // theme color e.g. "accent1"
    case gradient(stops: [(color: String, position: Int)])
    case noFill
}

// MARK: - Shape Outline

/// 形狀外框線
public struct ShapeOutline {
    public var color: String?    // hex RGB
    public var width: Int?       // EMU

    public init(color: String? = nil, width: Int? = nil) {
        self.color = color
        self.width = width
    }

    public var widthPoints: Double? {
        guard let w = width else { return nil }
        return Double(w) / 12700.0
    }
}
