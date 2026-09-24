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
