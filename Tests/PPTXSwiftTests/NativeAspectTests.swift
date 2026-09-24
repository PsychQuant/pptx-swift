import Testing
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
@testable import PPTXSwift

/// §1.3 — native pixel dimensions via ImageIO header-only decode.
///
/// Covers spec `pptx-metric-geometry` Requirement
/// "Native pixel dimensions are read via ImageIO header-only decode".
struct NativeAspectTests {

    // MARK: - Scenario: Raster image dimensions

    @Test func `1600x1200 PNG reports its native pixel dimensions`() throws {
        let png = try GeneratedImage.png(width: 1600, height: 1200)
        let dims = try NativeAspect.pixelDimensions(of: png)
        #expect(dims.width == 1600)
        #expect(dims.height == 1200)
    }

    @Test func `Portrait image keeps width and height in order`() throws {
        let png = try GeneratedImage.png(width: 300, height: 500)
        let dims = try NativeAspect.pixelDimensions(of: png)
        #expect(dims.width == 300)
        #expect(dims.height == 500)
    }

    // MARK: - Header-only read (review MEDIUM 4)

    /// Overwrites every IDAT payload byte of a PNG with 0x5A, leaving the
    /// signature, IHDR and chunk lengths intact: the header is valid, the
    /// compressed pixel stream is not a zlib stream at all.
    static func corruptingPixelData(of png: Data) throws -> Data {
        var bytes = [UInt8](png)
        var offset = 8                                   // after the PNG signature
        var corrupted = 0
        while offset + 8 <= bytes.count {
            let length = Int(bytes[offset]) << 24 | Int(bytes[offset + 1]) << 16
                | Int(bytes[offset + 2]) << 8 | Int(bytes[offset + 3])
            let type = String(decoding: bytes[(offset + 4)..<(offset + 8)], as: UTF8.self)
            let dataStart = offset + 8
            if type == "IDAT" {
                for i in dataStart..<(dataStart + length) { bytes[i] = 0x5A }
                corrupted += length
            }
            offset = dataStart + length + 4               // data + CRC
        }
        try #require(corrupted > 0, "PNG has no IDAT chunk to corrupt")
        return Data(bytes)
    }

    @Test func `Dimensions come from the header even when the pixel data is garbage`() throws {
        let png = try GeneratedImage.png(width: 1600, height: 1200)
        let corrupted = try Self.corruptingPixelData(of: png)
        #expect(corrupted.count == png.count)
        #expect(corrupted != png)

        let dims = try NativeAspect.pixelDimensions(of: corrupted)
        #expect(dims.width == 1600)
        #expect(dims.height == 1200)
    }

    // MARK: - Scenario: Undecodable media is a typed error

    static let undecodableSamples: [(label: String, data: Data)] = {
        let noise: [UInt8] = (0..<512).map { i in UInt8((i * 37 + 11) % 256) }
        var emfLike: [UInt8] = [0x01, 0x00, 0x00, 0x00, 0x6C, 0x00, 0x00, 0x00]
        emfLike += [UInt8](repeating: 0, count: 32)
        emfLike += Array(" EMF".utf8)
        return [
            ("non-image bytes", Data(noise)),
            ("empty data", Data()),
            ("EMF-like header", Data(emfLike)),
        ]
    }()

    @Test(arguments: undecodableSamples)
    func `Undecodable data throws a typed PPTXError`(label: String, data: Data) {
        let error = #expect(throws: PPTXError.self) {
            _ = try NativeAspect.pixelDimensions(of: data)
        }
        guard case .undecodableImage(let detail) = error else {
            Issue.record("\(label): expected .undecodableImage, got \(String(describing: error))")
            return
        }
        #expect(!detail.isEmpty)
        #expect(error?.errorDescription?.isEmpty == false)
        if label == "EMF-like header" {
            #expect(detail.contains("EMF"), "error should name the metafile format: \(detail)")
        }
    }
}

/// Programmatically drawn test images (CoreGraphics + ImageIO; no fixture files).
enum GeneratedImage {
    struct GenerationFailed: Error {}

    static func png(width: Int, height: Int) throws -> Data {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { throw GenerationFailed() }
        context.setFillColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        guard let image = context.makeImage() else { throw GenerationFailed() }

        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output, UTType.png.identifier as CFString, 1, nil
        ) else { throw GenerationFailed() }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw GenerationFailed() }
        return output as Data
    }
}
