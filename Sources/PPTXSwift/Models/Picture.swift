import Foundation

/// 圖片元素（對應 p:pic）
public struct Picture {
    public var id: Int
    public var name: String
    public var description: String?
    public var position: Position
    public var size: Size
    public var imageRelationshipId: String    // r:embed 的值

    public init(
        id: Int = 0,
        name: String = "",
        description: String? = nil,
        position: Position = Position(),
        size: Size = Size(),
        imageRelationshipId: String = ""
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.position = position
        self.size = size
        self.imageRelationshipId = imageRelationshipId
    }
}
