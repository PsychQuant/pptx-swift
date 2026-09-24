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

    /// MIME type by file extension (case-insensitive); `application/octet-stream`
    /// for an extension not in `contentTypesByExtension`.
    public var contentType: String {
        Self.contentTypesByExtension[fileExtension] ?? "application/octet-stream"
    }

    /// Media content types by lowercase file extension. The writer registers
    /// these as `[Content_Types].xml` `Default` entries; it types any other
    /// media part individually (see `MediaPartPlan`).
    static let contentTypesByExtension: [String: String] = [
        "png": "image/png",
        "jpg": "image/jpeg", "jpeg": "image/jpeg", "jpe": "image/jpeg", "jfif": "image/jpeg",
        "gif": "image/gif",
        "bmp": "image/bmp",
        "tif": "image/tiff", "tiff": "image/tiff",
        "emf": "image/x-emf",
        "wmf": "image/x-wmf",
        "svg": "image/svg+xml",
        "wdp": "image/vnd.ms-photo",
        "pdf": "application/pdf",
        "mp3": "audio/mpeg",
        "m4a": "audio/mp4",
        "wav": "audio/wav",
        "mp4": "video/mp4",
        "mov": "video/quicktime",
    ]
}
