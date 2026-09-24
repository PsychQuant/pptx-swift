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
    /// 外部連結圖片（`<a:blip r:link="...">`）所指的原始 Target（通常是 URL 或外部
    /// 檔案路徑）。讀檔時只在該 relationship 確實是 external（`TargetMode="External"`）
    /// 時才設定。`CT_Blip` 的 `r:embed`／`r:link` 是各自獨立的可選屬性（ECMA-376
    /// Part 1 §20.1.8.13），**可以同時出現**——PowerPoint「插入並連結」會同時留下
    /// 內嵌快取（`mediaFileName`）與指回原始檔案的連結（本欄位）；`PptxWriter` 兩者
    /// 都會寫出，不會因為有 `mediaFileName` 就丟掉本欄位（反之亦然）。
    public var externalImageTarget: String?
    /// `<a:srcRect>` of the picture's `blipFill` (crop); nil when absent.
    public var sourceRect: PictureSourceRect?

    public init(
        id: Int = 0,
        name: String = "",
        description: String? = nil,
        position: Position = Position(),
        size: Size = Size(),
        imageRelationshipId: String = "",
        mediaFileName: String? = nil,
        externalImageTarget: String? = nil,
        sourceRect: PictureSourceRect? = nil
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.position = position
        self.size = size
        self.imageRelationshipId = imageRelationshipId
        self.mediaFileName = mediaFileName
        self.externalImageTarget = externalImageTarget
        self.sourceRect = sourceRect
    }
}

/// The crop of a picture: its `blipFill`'s `<a:srcRect>` (ECMA-376 Part 1,
/// §20.1.8.55, `CT_RelativeRect`).
///
/// Each edge is how far that side of the image is moved inward, in
/// thousandths of a percent of the image's width (`left`, `right`) or height
/// (`top`, `bottom`): `100_000` is 100 %, `25_000` crops a quarter off that
/// side. A negative value moves the edge outward, adding empty space. The
/// visible part — what `a:stretch` fills the picture's frame with — is
/// `1 − (left + right) / 100_000` of the width and
/// `1 − (top + bottom) / 100_000` of the height.
public struct PictureSourceRect: Equatable {
    /// Scale of every edge: 100,000 = 100 %.
    public static let fullScale = 100_000

    public var left: Int
    public var top: Int
    public var right: Int
    public var bottom: Int

    public init(left: Int = 0, top: Int = 0, right: Int = 0, bottom: Int = 0) {
        self.left = left
        self.top = top
        self.right = right
        self.bottom = bottom
    }

    /// Whether every edge fits `xsd:int` (the transitional `ST_Percentage`
    /// the writer emits). `PptxWriter` refuses to write, and
    /// `NativeAspect` refuses to fit, a crop that does not: the reader could
    /// not read it back.
    public var isRepresentable: Bool {
        let range = Int(Int32.min)...Int(Int32.max)
        return [left, top, right, bottom].allSatisfy(range.contains)
    }

    /// Fraction of the image's width left visible (> 1 when extended).
    public var visibleWidthFraction: Double {
        1 - (Double(left) + Double(right)) / Double(Self.fullScale)
    }

    /// Fraction of the image's height left visible (> 1 when extended).
    public var visibleHeightFraction: Double {
        1 - (Double(top) + Double(bottom)) / Double(Self.fullScale)
    }
}
