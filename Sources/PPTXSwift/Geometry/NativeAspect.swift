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

// MARK: - Aspect fit

/// Which dimension of an extent is held fixed when fitting to native aspect.
public enum AspectAnchor: String, CaseIterable {
    case width
    case height
}

public extension NativeAspect {
    /// Keeps the anchored dimension of `size` and derives the other from the
    /// image's pixel aspect ratio, rounding half away from zero to whole EMU.
    ///
    /// Example: a 1600 × 1200 image anchored at width 3,600,000 EMU (10 cm)
    /// yields height 2,700,000 EMU (7.5 cm).
    ///
    /// - Throws: `PPTXError.invalidParameter` when the pixel dimensions are not
    ///   positive, or when the anchored dimension (checked before any
    ///   arithmetic) or the derived dimension lies outside
    ///   `1 ... PPTXMetric.maxCoordinateEmu`.
    static func fittedSize(
        keeping anchor: AspectAnchor, of size: Size, pixelWidth: Int, pixelHeight: Int
    ) throws -> Size {
        guard pixelWidth > 0, pixelHeight > 0 else {
            throw PPTXError.invalidParameter(
                "pixelDimensions", "像素尺寸必須大於 0（收到 \(pixelWidth) × \(pixelHeight)）"
            )
        }
        let anchored = anchor == .width ? size.width : size.height
        guard anchored > 0, anchored <= PPTXMetric.maxCoordinateEmu else {
            throw PPTXError.invalidParameter(
                anchor.rawValue,
                "錨定邊必須介於 1 與 \(PPTXMetric.maxCoordinateEmu) EMU 之間（收到 \(anchored)）"
            )
        }

        let ratio = anchor == .width
            ? Double(pixelHeight) / Double(pixelWidth)
            : Double(pixelWidth) / Double(pixelHeight)
        let derived = (Double(anchored) * ratio).rounded()
        guard derived >= 1, derived <= Double(PPTXMetric.maxCoordinateEmu) else {
            throw PPTXError.invalidParameter(
                anchor == .width ? "height" : "width",
                "依原生比例推得的尺寸超出 OOXML 座標範圍（\(derived) EMU）"
            )
        }

        return anchor == .width
            ? Size(width: anchored, height: Int(derived))
            : Size(width: Int(derived), height: anchored)
    }
}
