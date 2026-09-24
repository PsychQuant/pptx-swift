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
    public var geometry: ShapeGeometry
    public var position: Position
    public var size: Size
    /// 旋轉角度，語意與 `Shape.rotation` 完全相同（同一個 `a:xfrm`）。
    public var rotation: Int
    public var flipHorizontal: Bool
    public var flipVertical: Bool
    /// 線條樣式（顏色、寬度、兩端箭頭）。連接線最常見的視覺特徵——沒有箭頭的
    /// 連接線很少見——但 schema 上仍是可選的（`a:ln` 本身可以缺席）。
    public var outline: ShapeOutline?
    /// 起點連接目標（`p:cNvCxnSpPr/a:stCxn`）：連到哪個形狀的哪個連接點。
    /// `nil` 表示這一端是浮動的，沒有連到任何形狀。
    public var startConnection: ConnectionSite?
    /// 終點連接目標（`p:cNvCxnSpPr/a:endCxn`）。
    public var endConnection: ConnectionSite?
    /// 預設幾何的調整值（`a:prstGeom/a:avLst/a:gd`，ECMA-376 `CT_GeomGuideList`／
    /// `CT_GeomGuide`）。彎折／曲線連接線（`bentConnectorN`／`curvedConnectorN`）
    /// 的實際轉折點常常偏離預設路徑，靠這些調整值記錄；空陣列時省略
    /// `<a:avLst>` 內容（寫出空的 `<a:avLst/>`，維持沒有調整值時輸出與 #9
    /// 之前逐位元組相同）。Codex round 1 review 指出先前版本永遠寫空
    /// `<a:avLst/>`，會靜默丟棄讀進來的調整值——即使邊界框、旋轉、連接點都
    /// 沒變，連接線實際繞行的路徑仍可能因此跑掉。
    public var adjustments: [GeometryAdjustment]

    public init(
        id: Int = 0,
        name: String = "",
        geometry: ShapeGeometry = .straightConnector1,
        position: Position = Position(),
        size: Size = Size(),
        rotation: Int = 0,
        flipHorizontal: Bool = false,
        flipVertical: Bool = false,
        outline: ShapeOutline? = nil,
        startConnection: ConnectionSite? = nil,
        endConnection: ConnectionSite? = nil,
        adjustments: [GeometryAdjustment] = []
    ) {
        self.id = id
        self.name = name
        self.geometry = geometry
        self.position = position
        self.size = size
        self.rotation = rotation
        self.flipHorizontal = flipHorizontal
        self.flipVertical = flipVertical
        self.outline = outline
        self.startConnection = startConnection
        self.endConnection = endConnection
        self.adjustments = adjustments
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
