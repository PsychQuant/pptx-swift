import Foundation

/// 連接線／箭頭（對應 `p:cxnSp`，ECMA-376 Part 1 §19.3.1.19 `CT_Connector`）。
///
/// `spPr`（位置、大小、旋轉、翻轉、幾何、外框線）與 `p:sp`／`p:pic` 完全同一個
/// complex type（`a:CT_ShapeProperties`），因此讀寫路徑重用 `Shape`／`Picture`
/// 已有的 `parseShapeProperties`／`xfrmTransformAttributes` 共用 helper。連接線
/// 特有的只有兩端可能連到其他形狀的連接點（`a:stCxn`／`a:endCxn`）。
public struct Connector {
    public var id: Int
    public var name: String
    /// `EG_Geometry` 的完整內容，語意與 `Shape.geometryDefinition` 完全相同。
    /// 彎折／曲線連接線（`bentConnectorN`／`curvedConnectorN`）的實際轉折點常常
    /// 偏離預設路徑，靠 `.preset` 的調整值（`a:avLst/a:gd`）記錄。
    public var geometryDefinition: GeometryDefinition
    /// `geometryDefinition` 的型別化檢視，setter 語意與 `Shape.geometry` 相同。
    public var geometry: ShapeGeometry {
        get { geometryDefinition.typedView }
        set { geometryDefinition = geometryDefinition.replacingTypedView(with: newValue) }
    }
    /// 預設幾何的調整值；自訂路徑時為空陣列。唯讀。
    public var adjustments: [GeometryAdjustment] { geometryDefinition.adjustments }
    public var position: Position
    public var size: Size
    /// 旋轉角度，語意與 `Shape.rotation` 完全相同（同一個 `a:xfrm`）。
    public var rotation: Int
    public var flipHorizontal: Bool
    public var flipVertical: Bool
    /// `spPr` 的填色（`EG_FillProperties`），語意與 `Shape.fill` 相同。連接線本身
    /// 有填色在 schema 上合法但罕見（preset 連接線的路徑本來就 `fill="none"`）。
    public var fill: ShapeFill?
    /// 線條樣式（顏色、寬度、兩端箭頭）。連接線最常見的視覺特徵——沒有箭頭的
    /// 連接線很少見——但 schema 上仍是可選的（`a:ln` 本身可以缺席）。讀檔時保留
    /// 原始 XML，見 `ShapeOutline`。
    public var outline: ShapeOutline?
    /// 起點連接目標（`p:cNvCxnSpPr/a:stCxn`）：連到哪個形狀的哪個連接點。
    /// `nil` 表示這一端是浮動的，沒有連到任何形狀。
    public var startConnection: ConnectionSite?
    /// 終點連接目標（`p:cNvCxnSpPr/a:endCxn`）。
    public var endConnection: ConnectionSite?
    /// `p:style`（`CT_ShapeStyle`）的原始 XML，self-contained——與 `Shape.styleXML`
    /// 完全同一個機制與理由（PsychQuant/pptx-swift#11）。`shapes.pptx` 這個真實
    /// fixture 的三個連接線全部只靠這個（`lnRef idx="1"` 參照主題 `accent1`）取得
    /// 線條顏色，沒有一個帶明確的 `<a:ln><a:solidFill>`——這正是 #11 要修的、#10
    /// 修好表格後才第一次被完整往返測試觀察到的視覺遺失。
    public var styleXML: String?
    /// `CT_ShapeProperties` 裡沒有 typed 對應的子元素，原樣保存——與 `Shape` 的
    /// 同名欄位完全同一個機制與理由（PsychQuant/pptx-swift#12）。
    public var effectXML: String?
    public var scene3dXML: String?
    public var sp3dXML: String?
    public var extLstXML: String?
    /// `p:spPr` 的 `bwMode` 屬性，語意與 `Shape.blackWhiteMode` 相同。
    public var blackWhiteMode: String?

    public init(
        id: Int = 0,
        name: String = "",
        geometry: ShapeGeometry = .straightConnector1,
        position: Position = Position(),
        size: Size = Size(),
        rotation: Int = 0,
        flipHorizontal: Bool = false,
        flipVertical: Bool = false,
        fill: ShapeFill? = nil,
        outline: ShapeOutline? = nil,
        startConnection: ConnectionSite? = nil,
        endConnection: ConnectionSite? = nil,
        adjustments: [GeometryAdjustment] = [],
        styleXML: String? = nil,
        effectXML: String? = nil,
        scene3dXML: String? = nil,
        sp3dXML: String? = nil,
        extLstXML: String? = nil,
        blackWhiteMode: String? = nil
    ) {
        self.id = id
        self.name = name
        self.geometryDefinition = .preset(geometry.rawValue, adjustments: adjustments)
        self.position = position
        self.size = size
        self.rotation = rotation
        self.flipHorizontal = flipHorizontal
        self.flipVertical = flipVertical
        self.fill = fill
        self.outline = outline
        self.startConnection = startConnection
        self.endConnection = endConnection
        self.styleXML = styleXML
        self.effectXML = effectXML
        self.scene3dXML = scene3dXML
        self.sp3dXML = sp3dXML
        self.extLstXML = extLstXML
        self.blackWhiteMode = blackWhiteMode
    }
}

/// 一個預設幾何形狀的調整值（`a:gd`，ECMA-376 `CT_GeomGuide`）：`name` 是調整
/// 控點的代號（由形狀類型定義，例如 `adj1`／`adj2`），`formula` 是控制其位置的
/// 公式字串（例如 `"val 50000"`）。pptx-swift 不解析公式語意，只原樣往返。
public struct GeometryAdjustment: Equatable {
    public var name: String
    public var formula: String

    public init(name: String, formula: String) {
        self.name = name
        self.formula = formula
    }
}

/// 連接線一端連到的形狀連接點（`a:stCxn`／`a:endCxn`，ECMA-376 `CT_Connection`）。
public struct ConnectionSite: Equatable {
    /// 連到的形狀 `cNvPr/@id`（`ST_DrawingElementId`）。
    public var shapeId: Int
    /// 該形狀上第幾個連接點（`idx`，`xsd:unsignedInt`）。連接點的編號與數量由
    /// 形狀類型本身定義（例如矩形固定有 4 個，索引 0-3），pptx-swift 不驗證
    /// `idx` 對目標形狀類型是否合法——這是渲染器的責任，不是模型層的責任。
    public var index: Int

    public init(shapeId: Int, index: Int) {
        self.shapeId = shapeId
        self.index = index
    }
}
