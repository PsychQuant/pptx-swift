import Foundation
import ImageIO

/// Native pixel dimensions of embedded image media, read through ImageIO.
public enum NativeAspect {

    /// Reads the pixel width and height of `imageData` from its image header.
    ///
    /// Uses `CGImageSourceCopyPropertiesAtIndex` (`kCGImagePropertyPixelWidth` /
    /// `kCGImagePropertyPixelHeight`) with caching disabled, so the bitmap itself
    /// is never decoded — the cost is a header read, independent of image size.
    ///
    /// - Throws: `PPTXError.undecodableImage` when ImageIO cannot identify the
    ///   data as a raster image (including vector metafiles such as EMF/WMF), or
    ///   when the header carries no positive pixel size.
    public static func pixelDimensions(of imageData: Data) throws -> (width: Int, height: Int) {
        guard !imageData.isEmpty else {
            throw PPTXError.undecodableImage("圖片資料為空（0 bytes）")
        }

        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(imageData as CFData, options),
              CGImageSourceGetCount(source) > 0 else {
            throw PPTXError.undecodableImage(
                "ImageIO 無法辨識此影像格式（\(describeFormat(of: imageData))，\(imageData.count) bytes）"
            )
        }

        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, options) as? [CFString: Any],
              let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
              let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue,
              width > 0, height > 0 else {
            let type = (CGImageSourceGetType(source) as String?) ?? describeFormat(of: imageData)
            throw PPTXError.undecodableImage("ImageIO 讀不出像素尺寸（格式：\(type)）")
        }

        return (width, height)
    }

    /// Best-effort format label for error messages. Recognises the vector
    /// metafiles PowerPoint embeds but ImageIO cannot rasterise.
    static func describeFormat(of data: Data) -> String {
        let bytes = [UInt8](data.prefix(44))
        // EMF: ENHMETAHEADER.dSignature " EMF" at byte offset 40.
        if bytes.count >= 44, bytes[40...43].elementsEqual(Array(" EMF".utf8)) {
            return "EMF 向量 metafile"
        }
        // Placeable WMF: key 0x9AC6CDD7 (little-endian).
        if bytes.count >= 4, bytes[0...3].elementsEqual([0xD7, 0xCD, 0xC6, 0x9A]) {
            return "WMF 向量 metafile"
        }
        return "未知格式"
    }
}
