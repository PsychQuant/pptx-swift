import Foundation

/// 形狀（文字框、矩形、橢圓等）
public struct Shape {
    public var id: Int
    public var name: String
    public var placeholder: PlaceholderType?
    /// `EG_Geometry`（`<a:prstGeom>`｜`<a:custGeom>`）的完整內容：預設幾何的 `prst`
    /// 原字串與調整值，或自訂路徑的原樣 XML。這是幾何唯一的儲存位置——
    /// `geometry` 只是它的型別化檢視，兩者不可能分歧（見 `GeometryDefinition`）。
    public var geometryDefinition: GeometryDefinition
    /// `geometryDefinition` 的型別化檢視：預設幾何回傳對應的 `ShapeGeometry`
    /// （`prst` 不在列舉內時為 `.unknown`），自訂路徑回傳 `.custom`。
    ///
    /// 設定一個與目前檢視**不同**的值會把 `geometryDefinition` 換成該預設幾何
    /// （調整值清空——調整值的意義由形狀類型決定，換了形狀就不再適用），因此
    /// typed setter 一定勝過讀進來的自訂路徑，不會變成靜默的 no-op
    /// （PsychQuant/pptx-swift#12 審查 H2）。設定成與目前檢視**相同**的值不改動
    /// 任何東西（`shape.geometry = shape.geometry` 保留調整值與自訂路徑）。
    public var geometry: ShapeGeometry {
        get { geometryDefinition.typedView }
        set { geometryDefinition = geometryDefinition.replacingTypedView(with: newValue) }
    }
    /// 預設幾何的調整值（`a:avLst/a:gd`）；自訂路徑時為空陣列。唯讀——要改就
    /// 設定 `geometryDefinition`。
    public var adjustments: [GeometryAdjustment] { geometryDefinition.adjustments }
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
    /// `EG_FillProperties`。typed 值（`.solid`／`.schemeColor`／`.noFill`／
    /// `.gradient`）只在能完整重現原始 XML 時才由 `PptxReader` 產生，其餘（圖片
    /// 填色、圖樣、系統色、帶色彩變換的顏色……）一律是 `.raw`。typed 與原樣是同一個
    /// 欄位的兩種值，指定新的 typed 值就取代原樣內容（PsychQuant/pptx-swift#12 審查 H2）。
    public var fill: ShapeFill?
    /// `<a:ln>`。讀檔時保留原始 XML，寫出時只改寫被 typed 欄位改動過的部分，
    /// 見 `ShapeOutline`。
    public var outline: ShapeOutline?
    public var textBody: TextBody?
    /// `p:style`（`CT_ShapeStyle`, ECMA-376 §19.3.1.46）的exact original XML,
    /// self-contained (see `RawSlideElement.xml` / `PptxReader.selfContainedXMLString`
    /// for the same mechanism): a theme style reference — `lnRef`／`fillRef`／
    /// `effectRef`／`fontRef`, each a `<a:schemeClr>` plus a style-matrix index —
    /// that many PowerPoint-authored shapes rely on *instead of* an explicit
    /// `<a:ln>`／fill in `spPr` for their actual rendered color (PsychQuant/
    /// pptx-swift#11). Kept verbatim rather than parsed into typed fields:
    /// resolving a `schemeClr` to an actual color requires the *theme part*
    /// (`ppt/theme/theme1.xml`'s `<a:clrScheme>`), which is a document-level
    /// resource `Shape` has no access to — round-tripping the reference
    /// unparsed preserves the shape's real rendered appearance without
    /// requiring pptx-swift to become a full theme resolver. `nil` when the
    /// shape has no `p:style` (most synthetically-constructed shapes, and any
    /// shape whose color is fully explicit in `spPr`).
    ///
    /// `spPr` 裡的明確值覆寫 `p:style` 的主題參照，所以 `p:style` 只有在 `spPr`
    /// 的覆寫值（`fill`、`outline`）也完整保住時才能還原實際外觀。
    public var styleXML: String?
    /// `CT_ShapeProperties`（`p:spPr`）裡沒有 typed 對應的子元素，原樣保存、寫出時
    /// 放回 schema 正確位置（PsychQuant/pptx-swift#12）。每個欄位 `nil` 表示來源
    /// 形狀沒有這一段。`effectXML` 是 `EG_EffectProperties`（`<a:effectLst>` 或
    /// `<a:effectDag>`）；`scene3dXML`／`sp3dXML`／`extLstXML` 各自對應
    /// `<a:scene3d>`／`<a:sp3d>`／`<a:extLst>`。
    ///
    /// 原樣片段若引用 relationship（例如 `effectLst` 的 `a:blend` 裡的圖片），
    /// `PptxWriter` 會拒絕存檔，見 `Presentation.writeBlockers`。
    public var effectXML: String?
    public var scene3dXML: String?
    public var sp3dXML: String?
    public var extLstXML: String?
    /// `p:spPr` 的 `bwMode` 屬性（`ST_BlackWhiteMode`：`clr`／`auto`／`gray`／
    /// `ltGray`／`invGray`／`grayWhite`／`blackGray`／`blackWhite`／`black`／
    /// `white`／`hidden`），黑白列印／顯示時的呈現方式。原樣字串往返，`nil` 表示
    /// 沒有這個屬性。
    public var blackWhiteMode: String?

    public init(
        id: Int = 0,
        name: String = "",
        placeholder: PlaceholderType? = nil,
        geometry: ShapeGeometry = .rect,
        adjustments: [GeometryAdjustment] = [],
        position: Position = Position(),
        size: Size = Size(),
        rotation: Int = 0,
        flipHorizontal: Bool = false,
        flipVertical: Bool = false,
        fill: ShapeFill? = nil,
        outline: ShapeOutline? = nil,
        textBody: TextBody? = nil,
        styleXML: String? = nil,
        effectXML: String? = nil,
        scene3dXML: String? = nil,
        sp3dXML: String? = nil,
        extLstXML: String? = nil,
        blackWhiteMode: String? = nil
    ) {
        self.id = id
        self.name = name
        self.placeholder = placeholder
        self.geometryDefinition = .preset(geometry.rawValue, adjustments: adjustments)
        self.position = position
        self.size = size
        self.rotation = rotation
        self.flipHorizontal = flipHorizontal
        self.flipVertical = flipVertical
        self.fill = fill
        self.outline = outline
        self.textBody = textBody
        self.styleXML = styleXML
        self.effectXML = effectXML
        self.scene3dXML = scene3dXML
        self.sp3dXML = sp3dXML
        self.extLstXML = extLstXML
        self.blackWhiteMode = blackWhiteMode
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

/// 預設幾何形狀（`a:prstGeom` 的 `prst`，ECMA-376 `ST_ShapeType`）。這個列舉是
/// 一般形狀（`p:sp`）與連接線（`p:cxnSp`，見 `Connector`）共用的——`ST_ShapeType`
/// 本身就是同一個列舉同時涵蓋兩者，不是 pptx-swift 自己合併的。
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
    /// 哨兵值：`geometryDefinition` 是自訂路徑（`<a:custGeom>`）。不是
    /// `ST_ShapeType` 的值——預設幾何設成它時 `PptxWriter` 拒絕存檔。
    case custom
    /// 哨兵值：`prst` 不在這個列舉內（原字串保存在 `geometryDefinition`）。
    /// 不是 `ST_ShapeType` 的值——預設幾何設成它時 `PptxWriter` 拒絕存檔。
    case unknown

    // 連接線專用的預設幾何（PsychQuant/pptx-swift#9）。ECMA-376 `ST_ShapeType`
    // 定義的「彎折／曲線連接線」子集合，共 9 種，是封閉列舉。連接線也可以用
    // 上面已有的 `line`（純直線，無彎折點）——`shapes.pptx` 的三個連接線裡
    // 就有一個是 `prst="line"`——這 9 種只補上 `line` 沒涵蓋的彎折／曲線變化，
    // 不是「連接線只會出現這 9 種」（Codex round 1 review 指出既有措辭過強，
    // 已更正）。
    case straightConnector1
    case bentConnector2
    case bentConnector3
    case bentConnector4
    case bentConnector5
    case curvedConnector2
    case curvedConnector3
    case curvedConnector4
    case curvedConnector5
}

/// `EG_Geometry` 的完整內容（ECMA-376 `CT_PresetGeometry2D`｜`CT_CustomGeometry2D`）。
///
/// 預設幾何能被完整表達成「`prst` 字串＋調整值清單」（`CT_PresetGeometry2D` 只有
/// `prst` 屬性與可選的 `avLst`，`CT_GeomGuide` 只有 `name`／`fmla`），所以不需要
/// 原樣 XML；`prst` 保留原字串而不是 `ShapeGeometry`，因為 `ST_ShapeType` 有近
/// 190 種值，`ShapeGeometry` 只列了其中一部分——不在列舉內的值（例如
/// `chevron`）照樣原封不動地寫回，不會變成 `prst="unknown"`
/// （PsychQuant/pptx-swift#12 審查 M1）。自訂路徑（`<a:custGeom>`）沒有 typed
/// 模型，原樣保存。
public enum GeometryDefinition: Equatable {
    /// `<a:prstGeom prst="…">`：`prst` 原字串與 `a:avLst` 的調整值（空陣列寫成
    /// `<a:avLst/>`）。
    case preset(String, adjustments: [GeometryAdjustment])
    /// `<a:custGeom>` 的原樣 XML（self-contained，見 `RawSlideElement.xml`）。
    case custom(String)

    /// `Shape.geometry`／`Connector.geometry` 的型別化檢視。
    var typedView: ShapeGeometry {
        switch self {
        case .preset(let prst, _): return ShapeGeometry(rawValue: prst) ?? .unknown
        case .custom: return .custom
        }
    }

    /// typed setter 的語意：與目前檢視相同就不動（保留調整值與自訂路徑），
    /// 不同就換成該預設幾何、清空調整值。
    func replacingTypedView(with geometry: ShapeGeometry) -> GeometryDefinition {
        geometry == typedView ? self : .preset(geometry.rawValue, adjustments: [])
    }

    var adjustments: [GeometryAdjustment] {
        if case .preset(_, let adjustments) = self { return adjustments }
        return []
    }
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

/// 形狀填色（`EG_FillProperties`）
public enum ShapeFill {
    case solid(color: String)           // hex RGB e.g. "FF0000"
    case schemeColor(name: String)      // theme color e.g. "accent1"
    /// 線性漸層的色標（`position` 為 `ST_PositiveFixedPercentage`，0–100000）。
    /// 寫出成 `<a:gradFill><a:gsLst>…</a:gsLst></a:gradFill>`，至少要兩個色標。
    /// `PptxReader` 不會產生這個值——讀進來的漸層一律是 `.raw`（`a:lin`／
    /// `a:path`、色標的色彩變換等都沒有 typed 模型）。
    case gradient(stops: [(color: String, position: Int)])
    case noFill
    /// typed 值無法完整重現的填色，原樣保存的 XML（self-contained）：
    /// `<a:gradFill>`／`<a:blipFill>`／`<a:pattFill>`／`<a:grpFill>`，以及顏色
    /// 不是單純 `srgbClr`／`schemeClr`（系統色、預設色、HSL、scRGB、帶色彩變換）
    /// 的 `<a:solidFill>`（PsychQuant/pptx-swift#12 審查 H1／H2）。
    case raw(String)
}

// MARK: - Shape Outline

/// 形狀外框線（`a:ln`，ECMA-376 `CT_LineProperties`）
///
/// typed 欄位只涵蓋 `w`、單純的 `srgbClr` 實心線色與兩端端點；`<a:ln>` 其餘的
/// 部分（`noFill`、主題色、色彩變換、線條漸層、虛線、接合樣式、`cap`／`cmpd`／
/// `algn`、`extLst`）沒有 typed 模型。`PptxReader` 讀到的外框會記住原始 XML 與
/// 當時解析出的 typed 值，`PptxWriter` 寫出時：
///
/// - typed 欄位都沒改 → 原樣寫回原始 XML；
/// - 改了某些 typed 欄位 → 以原始 XML 為底，只改寫被改動的那幾個欄位（`w` 屬性、
///   線條填色、`headEnd`、`tailEnd`），其餘子元素與屬性原封不動。
///
/// 所以 typed setter 一定生效，而沒建模的部分也不會因為改了線寬就消失
/// （PsychQuant/pptx-swift#12 審查 H1；#13 列的遺失）。直接指定一個新建的
/// `ShapeOutline(...)` 就沒有原始 XML 可依，完全由 typed 欄位組出。
///
/// `color` 讀的是 `<a:solidFill><a:srgbClr val>`（直接子元素）；線色是主題色、
/// 漸層等時為 `nil`。把它改成某個值會把線條填色換成該實心色，改成 `nil`（原本
/// 有值時）會移除線條填色、讓 `p:style` 的 `lnRef` 接手。
public struct ShapeOutline {
    public var color: String?    // hex RGB
    public var width: Int?       // EMU
    /// 線條起點端點樣式（`a:ln/a:headEnd`）。任何形狀的 `a:ln` schema 上都允許，
    /// 但最常見於連接線（`p:cxnSp`，見 `Connector`）表示箭頭方向。
    public var headEnd: LineEndStyle?
    /// 線條終點端點樣式（`a:ln/a:tailEnd`）。
    public var tailEnd: LineEndStyle?
    /// 讀檔時的原始 `<a:ln>` 與當時解析出的 typed 值；`nil` 表示這個值不是
    /// 從檔案讀來的。
    var source: Source?

    struct Source {
        let xml: String
        let color: String?
        let width: Int?
        let headEnd: LineEndStyle?
        let tailEnd: LineEndStyle?
    }

    public init(color: String? = nil, width: Int? = nil, headEnd: LineEndStyle? = nil, tailEnd: LineEndStyle? = nil) {
        self.color = color
        self.width = width
        self.headEnd = headEnd
        self.tailEnd = tailEnd
    }

    /// 讀檔時的原始 `<a:ln>` XML（self-contained），不是從檔案讀來的外框為 `nil`。
    public var sourceXML: String? { source?.xml }

    public var widthPoints: Double? {
        guard let w = width else { return nil }
        return Double(w) / 12700.0
    }
}

/// 線條端點樣式（`a:headEnd`／`a:tailEnd`，ECMA-376 `CT_LineEndProperties`）。
/// 三個屬性都是可選的 enum-like 字串（`ST_LineEndType`／`ST_LineEndWidth`／
/// `ST_LineEndLength`），pptx-swift 原樣保留字串值、不轉型別化列舉——封閉集合小
/// 但沒有需要在 Swift 端做邏輯判斷的理由，原樣往返即可。
public struct LineEndStyle: Equatable {
    /// `type`（`ST_LineEndType`）：`none`／`triangle`／`stealth`／`diamond`／
    /// `oval`／`arrow`。
    public var type: String?
    /// `w`（`ST_LineEndWidth`）：`sm`／`med`／`lg`。
    public var width: String?
    /// `len`（`ST_LineEndLength`）：`sm`／`med`／`lg`。
    public var length: String?

    public init(type: String? = nil, width: String? = nil, length: String? = nil) {
        self.type = type
        self.width = width
        self.length = length
    }
}
