import Foundation

/// 圖片元素（對應 p:pic）
public struct Picture {
    public var id: Int
    public var name: String
    public var description: String?
    public var position: Position
    public var size: Size
    public var imageRelationshipId: String    // r:embed 的值
    /// r:embed 所指 media part 的檔名（ppt/media/ 下，例 "image1.png"）；
    /// 讀檔時由投影片 relationships 解析，無法解析時為 nil
    public var mediaFileName: String?

    public init(
        id: Int = 0,
        name: String = "",
        description: String? = nil,
        position: Position = Position(),
        size: Size = Size(),
        imageRelationshipId: String = "",
        mediaFileName: String? = nil
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.position = position
        self.size = size
        self.imageRelationshipId = imageRelationshipId
        self.mediaFileName = mediaFileName
    }
}
