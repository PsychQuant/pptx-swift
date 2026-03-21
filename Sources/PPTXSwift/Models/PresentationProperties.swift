import Foundation

/// 簡報屬性（對應 docProps/core.xml + app.xml）
public struct PresentationProperties {
    public var title: String?
    public var subject: String?
    public var creator: String?
    public var keywords: String?
    public var description: String?
    public var lastModifiedBy: String?
    public var revision: Int?
    public var created: Date?
    public var modified: Date?

    public init() {}
}

/// 媒體檔案（圖片、影片等，存放在 ppt/media/）
public struct MediaFile {
    public var id: String           // 檔案名稱或 relationship ID
    public var fileName: String     // e.g. "image1.png"
    public var data: Data

    public init(id: String, fileName: String, data: Data) {
        self.id = id
        self.fileName = fileName
        self.data = data
    }

    public var fileExtension: String {
        (fileName as NSString).pathExtension.lowercased()
    }

    public var contentType: String {
        switch fileExtension {
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "gif": return "image/gif"
        case "bmp": return "image/bmp"
        case "tiff", "tif": return "image/tiff"
        case "emf": return "image/x-emf"
        case "wmf": return "image/x-wmf"
        default: return "application/octet-stream"
        }
    }
}
