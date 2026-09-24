import Foundation

/// 圖形框架（對應 p:graphicFrame，用於表格、圖表等）
public struct GraphicFrame {
    public var id: Int
    public var name: String
    public var position: Position
    public var size: Size
    /// 旋轉角度（`p:xfrm` 的 `rot`，ECMA-376 `ST_Angle`：以 60,000 分之一度為單位的
    /// 整數，順時針為正）。`p:xfrm` 用的型別確實就是 `a:CT_Transform2D`——與形狀／
    /// 圖片的 `a:xfrm` 同一個 complex type，只是元素前綴依所在 schema
    /// （`CT_GraphicalObjectFrame`）而不同——`rot`／`flipH`／`flipV` 三個屬性合法
    /// 存在，寫出後是 schema-valid 的 XML（已用 datypic OOXML reference 與
    /// MS-OI29500 §20.1.7.6 交叉核對，非憑印象）。讀取時原樣保留；0（schema 預設）
    /// 表示未旋轉，寫出時省略 `rot` 屬性。正規化規則見 `PptxWriter`。
    ///
    /// **已知的跨應用程式落差（MS-OI29500 §20.1.7.6 明文的 deviation b）**：
    /// 「the standard allows attributes flipH, flipV and rot to be applied to
    /// a graphicFrame」但「In Office, attributes FlipH, flipV and rot are
    /// ignored when applied to a graphicFrame」——也就是說，這三個屬性合法、
    /// pptx-swift 正確地讀寫它們，但**真正的 Microsoft PowerPoint 開啟這個檔案時
    /// 會忽略它們**，表格視覺上不會旋轉／翻轉；LibreOffice 則不受此限，會照
    /// schema 字面套用（已用 headless `--convert-to pdf` 實測驗證：見 PR #7 報告
    /// 的「LibreOffice 驗證」段落）。pptx-swift 仍然正確地往返這三個屬性——若不
    /// 這樣做，一份原本就帶有 `rot` 的真實檔案（不論來源是哪個應用程式寫的）
    /// 讀進來再存出去會遺失這個值，正是這張 issue（#7）要修的那種靜默遺失。
    public var rotation: Int
    /// 是否沿垂直軸水平翻轉（`p:xfrm` 的 `flipH`）。同上，PowerPoint 忽略、
    /// LibreOffice 套用；讀寫本身正確，只是視覺結果因應用程式而異。
    public var flipHorizontal: Bool
    /// 是否沿水平軸垂直翻轉（`p:xfrm` 的 `flipV`）。同上。
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
