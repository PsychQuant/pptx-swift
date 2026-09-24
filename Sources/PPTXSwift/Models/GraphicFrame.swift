import Foundation

/// 圖形框架（對應 p:graphicFrame，用於表格、圖表等）
public struct GraphicFrame {
    public var id: Int
    public var name: String
    public var position: Position
    public var size: Size
    /// 旋轉角度（`p:xfrm` 的 `rot`，ECMA-376 `ST_Angle`：以 60,000 分之一度為單位的
    /// 整數，順時針為正）。`p:xfrm` 與形狀／圖片用的 `a:xfrm` 是同一個 complex type
    /// （`a:CT_Transform2D`），只是元素前綴依所在 schema（`CT_GraphicalObjectFrame`）
    /// 而不同，`rot`／`flipH`／`flipV` 三個屬性完全比照辦理。讀取時原樣保留；0
    /// （schema 預設）表示未旋轉，寫出時省略 `rot` 屬性。正規化規則見 `PptxWriter`。
    public var rotation: Int
    /// 是否沿垂直軸水平翻轉（`p:xfrm` 的 `flipH`）。
    public var flipHorizontal: Bool
    /// 是否沿水平軸垂直翻轉（`p:xfrm` 的 `flipV`）。
    public var flipVertical: Bool
    public var table: DrawingTable?

    public init(
        id: Int = 0,
        name: String = "",
        position: Position = Position(),
        size: Size = Size(),
        rotation: Int = 0,
        flipHorizontal: Bool = false,
        flipVertical: Bool = false,
        table: DrawingTable? = nil
    ) {
        self.id = id
        self.name = name
        self.position = position
        self.size = size
        self.rotation = rotation
        self.flipHorizontal = flipHorizontal
        self.flipVertical = flipVertical
        self.table = table
    }
}

// MARK: - Drawing Table

/// DrawingML 表格（對應 a:tbl）
public struct DrawingTable {
    public var columns: [TableColumn]
    public var rows: [TableRow]

    public init(columns: [TableColumn] = [], rows: [TableRow] = []) {
        self.columns = columns
        self.rows = rows
    }

    public var columnCount: Int { columns.count }
    public var rowCount: Int { rows.count }

    /// 取得表格純文字
    public func getText() -> String {
        rows.map { row in
            row.cells.map { $0.getText() }.joined(separator: "\t")
        }.joined(separator: "\n")
    }

    /// 取得儲存格文字
    public func getCellText(row: Int, col: Int) -> String? {
        guard row >= 0 && row < rows.count else { return nil }
        guard col >= 0 && col < rows[row].cells.count else { return nil }
        return rows[row].cells[col].getText()
    }

    /// 更新儲存格文字
    public mutating func updateCell(row: Int, col: Int, text: String) throws {
        guard row >= 0 && row < rows.count else {
            throw PPTXError.invalidIndex(row)
        }
        guard col >= 0 && col < rows[row].cells.count else {
            throw PPTXError.invalidIndex(col)
        }
        rows[row].cells[col].textBody = TextBody(paragraphs: [TextParagraph(text: text)])
    }
}

public struct TableColumn {
    public var width: Int  // EMU

    public init(width: Int = 0) {
        self.width = width
    }
}

public struct TableRow {
    public var height: Int   // EMU
    public var cells: [TableCell]

    public init(height: Int = 0, cells: [TableCell] = []) {
        self.height = height
        self.cells = cells
    }
}

public struct TableCell {
    public var textBody: TextBody

    public init(textBody: TextBody = TextBody()) {
        self.textBody = textBody
    }

    public init(text: String) {
        self.textBody = TextBody(paragraphs: [TextParagraph(text: text)])
    }

    public func getText() -> String {
        textBody.getText()
    }
}
