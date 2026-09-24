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
        endConnection: ConnectionSite? = nil
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
