import Foundation

/// 投影片
public struct Slide {
    public var elements: [SlideElement]
    public var notes: String?
    public var transition: SlideTransition?
    public var layoutReference: String?     // slideLayout 的 rId
    public var masterReference: String?     // slideMaster 的 rId

    public init(
        elements: [SlideElement] = [],
        notes: String? = nil,
        transition: SlideTransition? = nil,
        layoutReference: String? = nil
    ) {
        self.elements = elements
        self.notes = notes
        self.transition = transition
        self.layoutReference = layoutReference
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
