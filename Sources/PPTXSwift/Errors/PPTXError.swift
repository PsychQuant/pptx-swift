import Foundation

/// PPTX 處理相關錯誤
public enum PPTXError: Error, LocalizedError {
    case fileNotFound(String)
    case parseError(String)
    case invalidFormat(String)
    case zipError(String)
    case invalidIndex(Int)
    case invalidParameter(String, String)
    case writeError(String)
    /// ImageIO 無法從資料讀出點陣圖像素尺寸（含 EMF/WMF 等向量 metafile）
    case undecodableImage(String)
    /// 元素位於群組（GroupShape）內或本身即為群組：父層 transform 會疊加，公分幾何設定不支援
    case groupGeometryUnsupported(shapeId: Int)
    /// 元素是 `RawSlideElement`（pptx-swift 無法解析成型別化結構的子元素，例如
    /// `mc:AlternateContent`／`p:contentPart`）：沒有可設定的幾何欄位
    /// （PsychQuant/pptx-swift#9）
    case rawElementGeometryUnsupported(shapeId: Int)

    public var errorDescription: String? {
        switch self {
        case .fileNotFound(let path):
            return "找不到檔案: \(path)"
        case .parseError(let msg):
            return "解析錯誤: \(msg)"
        case .invalidFormat(let msg):
            return "格式無效: \(msg)"
        case .zipError(let msg):
            return "ZIP 錯誤: \(msg)"
        case .invalidIndex(let index):
            return "索引超出範圍: \(index)"
        case .invalidParameter(let name, let msg):
            return "參數錯誤 \(name): \(msg)"
        case .writeError(let msg):
            return "寫入錯誤: \(msg)"
        case .undecodableImage(let msg):
            return "無法解碼圖片: \(msg)"
        case .groupGeometryUnsupported(let shapeId):
            return "形狀 id=\(shapeId) 位於群組內或本身即為群組：群組子元素的座標會與父層 transform 疊加，目前不支援設定群組幾何"
        case .rawElementGeometryUnsupported(let shapeId):
            return "id=\(shapeId) 是未建模的原始 XML 內容（例如 mc:AlternateContent／p:contentPart），沒有可設定的幾何欄位"
        }
    }
}
