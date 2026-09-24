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
    public var elements: [SlideElement]

    public init(
        id: Int = 0,
        name: String = "",
        position: Position = Position(),
        size: Size = Size(),
        childOffset: Position? = nil,
        childExtent: Size? = nil,
        elements: [SlideElement] = []
    ) {
        self.id = id
        self.name = name
        self.position = position
        self.size = size
        self.childOffset = childOffset ?? position
        self.childExtent = childExtent ?? size
        self.elements = elements
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
            }
        }
        .filter { !$0.isEmpty }
        .joined(separator: "\n")
    }
}
