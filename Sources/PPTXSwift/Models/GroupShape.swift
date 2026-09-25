import Foundation

/// 群組形狀（對應 p:grpSp）
public struct GroupShape {
    public var id: Int
    public var name: String
    /// 群組本身在父座標系（投影片或外層群組）中的位置（`a:off`）
    public var position: Position
    /// 群組本身在父座標系中的大小（`a:ext`）
    public var size: Size
    /// 子座標系的原點（`a:chOff`）：群組內每個子元素的 `a:off`／`a:ext` 都是在這個
    /// 座標系底下量測的，與 `position`／`size` 之間的差異定義出子元素要被縮放、平移
    /// 多少才會落在投影片的實際位置上。未指定時預設等於 `position`（即無縮放）。
    public var childOffset: Position
    /// 子座標系的大小（`a:chExt`）。未指定時預設等於 `size`（即無縮放）。
    public var childExtent: Size
    /// 旋轉角度（`a:xfrm` 的 `rot`，ECMA-376 `ST_Angle`：以 60,000 分之一度為單位的
    /// 整數，順時針為正）。群組的 `grpSpPr/a:xfrm` 型別是 `a:CT_GroupTransform2D`
    /// （比 `CT_Transform2D` 多 `chOff`／`chExt`），`rot`／`flipH`／`flipV` 三個屬性與
    /// 一般形狀完全相同、套用在群組整體的外框（`position`／`size`）上，不影響子座標系
    /// 的縮放平移（`childOffset`／`childExtent`）換算。讀取時原樣保留；0（schema 預設）
    /// 表示未旋轉，寫出時省略 `rot` 屬性。正規化規則見 `PptxWriter`。
    public var rotation: Int
    /// 是否沿垂直軸水平翻轉（`a:xfrm` 的 `flipH`）。
    public var flipHorizontal: Bool
    /// 是否沿水平軸垂直翻轉（`a:xfrm` 的 `flipV`）。
    public var flipVertical: Bool
    public var elements: [SlideElement]
    /// `CT_GroupShapeProperties`（`p:grpSpPr`）子元素 pptx-swift 沒有型別化模型
    /// 的部分，原樣保存、寫出時放回 schema 正確位置（PsychQuant/pptx-swift#12）。
    /// `grpSpPr` 的 schema 序列是 `xfrm?, EG_FillProperties?, EG_EffectProperties?,
    /// scene3d?, extLst?`——跟 `CT_ShapeProperties`（`Shape`／`Connector` 用的
    /// 那個）不同：**沒有** `EG_Geometry`（不能是 custGeom／prstGeom，群組本身
    /// 沒有外框路徑）也**沒有** `a:ln`／`a:sp3d`。`GroupShape` 目前完全沒有型別化
    /// 的 `fill` 欄位，所以 `rawFillXML` 是單純原樣保留，不像 `Shape.rawFillXML`
    /// 有互斥的 typed 版本。
    public var rawFillXML: String?
    public var effectXML: String?
    public var scene3dXML: String?
    public var extLstXML: String?

    public init(
        id: Int = 0,
        name: String = "",
        position: Position = Position(),
        size: Size = Size(),
        childOffset: Position? = nil,
        childExtent: Size? = nil,
        rotation: Int = 0,
        flipHorizontal: Bool = false,
        flipVertical: Bool = false,
        elements: [SlideElement] = [],
        rawFillXML: String? = nil,
        effectXML: String? = nil,
        scene3dXML: String? = nil,
        extLstXML: String? = nil
    ) {
        self.id = id
        self.name = name
        self.position = position
        self.size = size
        self.childOffset = childOffset ?? position
        self.childExtent = childExtent ?? size
        self.rotation = rotation
        self.flipHorizontal = flipHorizontal
        self.flipVertical = flipVertical
        self.elements = elements
        self.rawFillXML = rawFillXML
        self.effectXML = effectXML
        self.scene3dXML = scene3dXML
        self.extLstXML = extLstXML
    }

    /// 取得群組內所有文字
    public func getText() -> String {
        elements.compactMap { element -> String? in
            switch element {
            case .shape(let shape):
                return shape.textBody?.getText()
            case .picture:
                return nil
            case .graphicFrame(let frame):
                return frame.table?.getText()
            case .group(let group):
                return group.getText()
            case .connector:
                return nil
            case .raw:
                return nil
            }
        }
        .filter { !$0.isEmpty }
        .joined(separator: "\n")
    }
}
