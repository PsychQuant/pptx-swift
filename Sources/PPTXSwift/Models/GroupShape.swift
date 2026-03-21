import Foundation

/// 群組形狀（對應 p:grpSp）
public struct GroupShape {
    public var id: Int
    public var name: String
    public var position: Position
    public var size: Size
    public var elements: [SlideElement]

    public init(
        id: Int = 0,
        name: String = "",
        position: Position = Position(),
        size: Size = Size(),
        elements: [SlideElement] = []
    ) {
        self.id = id
        self.name = name
        self.position = position
        self.size = size
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
