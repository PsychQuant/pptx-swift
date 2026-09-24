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
        }
    }
}
