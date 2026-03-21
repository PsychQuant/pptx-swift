import Foundation

/// 文字主體（對應 p:txBody）
public struct TextBody {
    public var paragraphs: [TextParagraph]
    public var bodyProperties: BodyProperties

    public init(
        paragraphs: [TextParagraph] = [],
        bodyProperties: BodyProperties = BodyProperties()
    ) {
        self.paragraphs = paragraphs
        self.bodyProperties = bodyProperties
    }

    /// 取得純文字
    public func getText() -> String {
        paragraphs.map { $0.getText() }.joined(separator: "\n")
    }
}

// MARK: - Text Paragraph

/// 文字段落（對應 a:p）
public struct TextParagraph {
    public var runs: [TextRun]
    public var properties: TextParagraphProperties
    public var bullet: BulletStyle?

    public init(
        runs: [TextRun] = [],
        properties: TextParagraphProperties = TextParagraphProperties(),
        bullet: BulletStyle? = nil
    ) {
        self.runs = runs
        self.properties = properties
        self.bullet = bullet
    }

    /// 便利初始化：直接用文字
    public init(text: String) {
        self.runs = [TextRun(text: text)]
        self.properties = TextParagraphProperties()
        self.bullet = nil
    }

    /// 取得段落純文字
    public func getText() -> String {
        runs.map { $0.text }.joined()
    }
}

// MARK: - Text Run

/// 文字區段（對應 a:r）
public struct TextRun {
    public var text: String
    public var properties: TextRunProperties

    public init(text: String, properties: TextRunProperties = TextRunProperties()) {
        self.text = text
        self.properties = properties
    }
}

// MARK: - Text Run Properties

/// 文字格式屬性（對應 a:rPr）
public struct TextRunProperties {
    public var fontSize: Int?         // 百分之一 point（e.g. 4400 = 44pt）
    public var bold: Bool?
    public var italic: Bool?
    public var underline: String?     // "sng", "dbl", etc.
    public var strikethrough: String? // "sngStrike", "dblStrike"
    public var fontName: String?
    public var color: String?         // hex RGB
    public var schemeColor: String?   // theme color name
    public var language: String?

    public init() {}

    /// 字體大小（point）
    public var fontSizePoints: Double? {
        guard let sz = fontSize else { return nil }
        return Double(sz) / 100.0
    }
}

// MARK: - Text Paragraph Properties

/// 段落格式屬性（對應 a:pPr）
public struct TextParagraphProperties {
    public var alignment: TextAlignment?
    public var level: Int?           // 縮排層級 (0-8)
    public var lineSpacing: Int?     // 百分比（e.g. 100000 = 100%）
    public var spaceBefore: Int?     // 段前間距
    public var spaceAfter: Int?      // 段後間距

    public init() {}
}

public enum TextAlignment: String {
    case left = "l"
    case center = "ctr"
    case right = "r"
    case justify = "just"
    case distributed = "dist"
}

// MARK: - Bullet Style

/// 項目符號樣式
public enum BulletStyle {
    case character(char: String, font: String?)
    case autoNumbered(type: String, startAt: Int?)
    case none
}

// MARK: - Body Properties

/// 文字框屬性（對應 a:bodyPr）
public struct BodyProperties {
    public var wrap: String?         // "square", "none"
    public var anchor: String?       // "t", "ctr", "b"
    public var autoFit: AutoFitType?
    public var margins: TextMargins?

    public init() {}
}

public enum AutoFitType {
    case normal
    case shrinkText
    case noAutoFit
}

public struct TextMargins {
    public var top: Int?     // EMU
    public var bottom: Int?
    public var left: Int?
    public var right: Int?

    public init(top: Int? = nil, bottom: Int? = nil, left: Int? = nil, right: Int? = nil) {
        self.top = top
        self.bottom = bottom
        self.left = left
        self.right = right
    }
}
