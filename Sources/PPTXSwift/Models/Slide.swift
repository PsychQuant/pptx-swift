import Foundation

/// 投影片
public struct Slide {
    public var elements: [SlideElement]
    public var notes: String?
    public var transition: SlideTransition?
    public var layoutReference: String?     // slideLayout 的 rId
    public var masterReference: String?     // slideMaster 的 rId
    /// 投影片 XML 含 DrawingML `EG_Media` 的任一種（`a:audioFile`、`a:videoFile`、
    /// `a:wavAudioFile`、`a:audioCd`、`a:quickTimeFile`），或換場音效（PresentationML
    /// 的 `p:snd`）。偵測時核對命名空間，不只看 local name。
    /// pptx-swift 目前不建模播放觸發與時間軸（`p:timing`），`PptxWriter` 遇到這種
    /// 投影片會拒絕寫出（見 PsychQuant/pptx-swift#5），不要默默遺失內容。
    public var containsUnsupportedMedia: Bool

    public init(
        elements: [SlideElement] = [],
        notes: String? = nil,
        transition: SlideTransition? = nil,
        layoutReference: String? = nil,
        containsUnsupportedMedia: Bool = false
    ) {
        self.elements = elements
        self.notes = notes
        self.transition = transition
        self.layoutReference = layoutReference
        self.containsUnsupportedMedia = containsUnsupportedMedia
    }

    /// 取得投影片純文字
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
                // 未建模的原始 XML（PsychQuant/pptx-swift#9）：內容不透明，
                // 不嘗試從中挖文字。
                return nil
            }
        }
        .filter { !$0.isEmpty }
        .joined(separator: "\n")
    }

    /// 取得所有形狀
    public var shapes: [Shape] {
        elements.compactMap {
            if case .shape(let s) = $0 { return s }
            return nil
        }
    }

    /// 取得所有圖片
    public var pictures: [Picture] {
        elements.compactMap {
            if case .picture(let p) = $0 { return p }
            return nil
        }
    }

    /// 取得所有表格
    public var tables: [GraphicFrame] {
        elements.compactMap {
            if case .graphicFrame(let f) = $0, f.table != nil { return f }
            return nil
        }
    }
}

// MARK: - Slide Element

/// 投影片元素（Shape Tree 的子元素）
public enum SlideElement {
    case shape(Shape)
    case picture(Picture)
    case graphicFrame(GraphicFrame)
    case group(GroupShape)
    /// 連接線／箭頭（`p:cxnSp`，PsychQuant/pptx-swift#9）。
    case connector(Connector)
    /// pptx-swift 無法解析成型別化結構的子元素（`mc:AlternateContent`、
    /// `p:contentPart`、或任何未來的未知元素），原樣保留其 XML
    /// （PsychQuant/pptx-swift#9）。
    case raw(RawSlideElement)
}

// MARK: - Slide Transition

/// 投影片轉場效果
public struct SlideTransition {
    public var type: TransitionType
    public var speed: TransitionSpeed

    public init(type: TransitionType = .none, speed: TransitionSpeed = .medium) {
        self.type = type
        self.speed = speed
    }
}

public enum TransitionType: String {
    case none
    case fade
    case push
    case wipe
    case split
    case cover
    case uncover
    case dissolve
    case random
    case unknown
}

public enum TransitionSpeed: String {
    case slow
    case medium = "med"
    case fast
}
