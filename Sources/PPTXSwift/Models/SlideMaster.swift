import Foundation

/// 投影片母片（對應 slideMaster1.xml）
public struct SlideMaster {
    public var id: String
    public var placeholders: [PlaceholderDef]
    public var colorMapOverrides: [String: String]?
    public var layoutReferences: [String]     // 關聯的 slideLayout rId

    public init(
        id: String = "",
        placeholders: [PlaceholderDef] = [],
        colorMapOverrides: [String: String]? = nil,
        layoutReferences: [String] = []
    ) {
        self.id = id
        self.placeholders = placeholders
        self.colorMapOverrides = colorMapOverrides
        self.layoutReferences = layoutReferences
    }
}

/// 投影片版面配置（對應 slideLayout1.xml）
public struct SlideLayout {
    public var id: String
    public var name: String
    public var type: String?             // "title", "obj", "blank", etc.
    public var placeholders: [PlaceholderDef]
    public var masterReference: String?  // slideMaster 的 rId

    public init(
        id: String = "",
        name: String = "",
        type: String? = nil,
        placeholders: [PlaceholderDef] = [],
        masterReference: String? = nil
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.placeholders = placeholders
        self.masterReference = masterReference
    }
}

/// 佔位符定義
public struct PlaceholderDef {
    public var type: PlaceholderType
    public var index: Int?
    public var position: Position
    public var size: Size

    public init(
        type: PlaceholderType = .unknown,
        index: Int? = nil,
        position: Position = Position(),
        size: Size = Size()
    ) {
        self.type = type
        self.index = index
        self.position = position
        self.size = size
    }
}
