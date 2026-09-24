import Foundation

/// PowerPoint 簡報結構
public struct Presentation {
    public var slides: [Slide]
    public var slideMasters: [SlideMaster]
    public var slideLayouts: [SlideLayout]
    public var theme: Theme?
    public var properties: PresentationProperties
    public var images: [MediaFile]
    public var slideSize: SlideSize

    public init() {
        self.slides = []
        self.slideMasters = []
        self.slideLayouts = []
        self.theme = nil
        self.properties = PresentationProperties()
        self.images = []
        self.slideSize = SlideSize()
    }

    // MARK: - Text Operations

    /// 取得整份簡報的純文字
    public func getText() -> String {
        slides.enumerated().map { index, slide in
            let slideText = slide.getText()
            return slideText.isEmpty ? "" : "--- Slide \(index + 1) ---\n\(slideText)"
        }
        .filter { !$0.isEmpty }
        .joined(separator: "\n\n")
    }

    /// 取得投影片數量
    public var slideCount: Int { slides.count }

    // MARK: - Slide Operations

    /// 新增投影片
    public mutating func addSlide(_ slide: Slide) {
        slides.append(slide)
    }

    /// 刪除投影片
    public mutating func deleteSlide(at index: Int) throws {
        guard index >= 0 && index < slides.count else {
            throw PPTXError.invalidIndex(index)
        }
        slides.remove(at: index)
    }

    /// 重新排列投影片
    public mutating func reorderSlide(from sourceIndex: Int, to destinationIndex: Int) throws {
        guard sourceIndex >= 0 && sourceIndex < slides.count else {
            throw PPTXError.invalidIndex(sourceIndex)
        }
        guard destinationIndex >= 0 && destinationIndex < slides.count else {
            throw PPTXError.invalidIndex(destinationIndex)
        }
        let slide = slides.remove(at: sourceIndex)
        slides.insert(slide, at: destinationIndex)
    }

    /// 複製投影片
    public mutating func duplicateSlide(at index: Int) throws -> Int {
        guard index >= 0 && index < slides.count else {
            throw PPTXError.invalidIndex(index)
        }
        let copy = slides[index]
        slides.insert(copy, at: index + 1)
        return index + 1
    }

    // MARK: - Media

    /// 取得圖片元素所嵌入的 media 檔（依 `Picture.mediaFileName` 比對 `MediaFile.fileName`）；
    /// 圖片未連結 media 或 media 不存在時回傳 nil
    public func mediaFile(for picture: Picture) -> MediaFile? {
        guard let name = picture.mediaFileName else { return nil }
        return images.first { $0.fileName == name }
    }

    // MARK: - Info

    public struct Info {
        public let slideCount: Int
        public let width: Int        // EMU
        public let height: Int       // EMU
        public let title: String?
        public let author: String?
    }

    public func getInfo() -> Info {
        Info(
            slideCount: slides.count,
            width: slideSize.width,
            height: slideSize.height,
            title: properties.title,
            author: properties.creator
        )
    }
}

// MARK: - Slide Size

/// 投影片尺寸（EMU 單位）
public struct SlideSize {
    public var width: Int    // cx，預設 10 inch = 9144000 EMU
    public var height: Int   // cy，預設 7.5 inch = 6858000 EMU

    public init(width: Int = 9144000, height: Int = 6858000) {
        self.width = width
        self.height = height
    }

    public var widthInches: Double { Double(width) / 914400.0 }
    public var heightInches: Double { Double(height) / 914400.0 }
    public var widthPoints: Double { Double(width) / 12700.0 }
    public var heightPoints: Double { Double(height) / 12700.0 }
}
