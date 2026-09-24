import Testing
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import OOXMLSwift
@testable import PPTXSwift

/// PsychQuant/pptx-swift#2: native aspect is the aspect of what is shown —
/// the image turned upright by its EXIF orientation, then cropped by the
/// picture's `<a:srcRect>` — not the stored pixel grid.
struct CropAndOrientationTests {

    // MARK: - EXIF orientation

    /// EXIF orientations 5–8 turn the image by 90° or 270° (with or without
    /// a mirror); 1–4 keep its axes.
    @Test(arguments: 1...8)
    func `EXIF orientations that turn the image by 90 or 270 degrees swap width and height`(orientation: Int) throws {
        let jpeg = try GeneratedImage.jpeg(width: 1600, height: 1200, orientation: orientation)
        let dims = try NativeAspect.pixelDimensions(of: jpeg)
        if (5...8).contains(orientation) {
            #expect(dims.width == 1200 && dims.height == 1600, "orientation \(orientation): \(dims)")
        } else {
            #expect(dims.width == 1600 && dims.height == 1200, "orientation \(orientation): \(dims)")
        }
    }

    static let orientationValues: [(label: String, value: Any?, swaps: Bool)] = [
        ("absent", nil, false),
        ("0 (not a valid EXIF value)", NSNumber(value: 0), false),
        ("9 (not a valid EXIF value)", NSNumber(value: 9), false),
        ("-6", NSNumber(value: -6), false),
        ("a string", "6", false),
        ("5", NSNumber(value: 5), true),
        ("8", NSNumber(value: 8), true),
    ]

    @Test(arguments: orientationValues.indices)
    func `Only EXIF orientations 5 to 8 swap axes; absent or unrecognised values keep them`(index: Int) {
        let c = Self.orientationValues[index]
        #expect(NativeAspect.swapsAxes(orientation: c.value) == c.swaps, "\(c.label)")
    }

    @Test func `An image without an orientation tag keeps its stored axes`() throws {
        let png = try GeneratedImage.png(width: 1600, height: 1200)
        let dims = try NativeAspect.pixelDimensions(of: png)
        #expect(dims.width == 1600 && dims.height == 1200)
    }

    @Test func `An upright portrait photo fits as portrait`() throws {
        // Stored landscape, shown portrait: a 10 cm wide fit must be taller than wide.
        let jpeg = try GeneratedImage.jpeg(width: 1600, height: 1200, orientation: 6)
        let dims = try NativeAspect.pixelDimensions(of: jpeg)
        let fitted = try NativeAspect.fittedSize(keeping: .width, of: Size(width: 3_600_000, height: 1),
                                                 pixelWidth: dims.width, pixelHeight: dims.height)
        #expect(fitted.height == 4_800_000)
    }

    // MARK: - srcRect model

    @Test func `The reader models each picture's srcRect from cropped.pptx`() throws {
        let url = try #require(RealFileTests.fixturePath("cropped.pptx"))
        let pres = try PptxReader.read(from: url)
        let byId = Dictionary(uniqueKeysWithValues: Self.allPictures(in: pres.slides[0].elements).map { ($0.id, $0.sourceRect) })
        #expect(byId.count == 6)
        #expect(byId[5] == .some(nil), "picture 5 has no srcRect")
        #expect(byId[8] == PictureSourceRect(top: 52_941, bottom: -17_647))
        #expect(byId[10] == PictureSourceRect(left: 2_878, top: 2_522, right: 21_582, bottom: 46_217))
        #expect(byId[12] == PictureSourceRect(left: 3_631, top: 5_869, right: 985, bottom: 25_394))
        // 14 and 16 sit two groups deep and share the reader's picture parsing.
        #expect(byId[14] == PictureSourceRect(top: 52_941, bottom: -17_647))
        #expect(byId[16] == PictureSourceRect(left: 2_878, top: 2_522, right: 21_582, bottom: 46_217))
    }

    static func allPictures(in elements: [SlideElement]) -> [Picture] {
        elements.flatMap { element -> [Picture] in
            switch element {
            case .picture(let picture): return [picture]
            case .group(let group): return allPictures(in: group.elements)
            case .shape, .graphicFrame: return []
            }
        }
    }

    static let percentageCases: [(text: String, value: Int?)] = [
        ("52941", 52_941),
        ("-17647", -17_647),
        ("0", 0),
        ("52.941%", 52_941),       // strict-schema ST_Percentage form
        ("-17.647%", -17_647),
        ("100%", 100_000),
        (" 25% ", 25_000),
        ("abc", nil),
        ("", nil),
        ("1e400%", nil),
        ("99999999999999999999", nil),
    ]

    @Test(arguments: percentageCases)
    func `srcRect edges parse integer and percent-string forms`(c: (text: String, value: Int?)) {
        #expect(PptxReader.parsePercentage(c.text) == c.value)
    }

    @Test func `srcRect written as percent strings reads the same as the integer form`() throws {
        let url = try PictureMediaTests.tamperedSlide(replacing: [
            (#"<a:srcRect l="2878" t="2522" r="21582" b="46217"/>"#,
             #"<a:srcRect l="2.878%" t="2.522%" r="21.582%" b="46.217%"/>"#),
        ])
        defer { try? FileManager.default.removeItem(at: url) }
        let pres = try PptxReader.read(from: url)
        let picture = try #require(pres.slides.flatMap(\.pictures).first { $0.id == 10 })
        #expect(picture.sourceRect == PictureSourceRect(left: 2_878, top: 2_522, right: 21_582, bottom: 46_217))
    }

    // MARK: - Fit with crop

    @Test func `Fit uses the visible area left after cropping`() throws {
        // 1600 × 1200 with 12.5 % off each side: 1200 × 1200 visible → square.
        let crop = PictureSourceRect(left: 12_500, right: 12_500)
        let byWidth = try NativeAspect.fittedSize(keeping: .width, of: Size(width: 3_600_000, height: 1),
                                                  pixelWidth: 1600, pixelHeight: 1200, crop: crop)
        #expect(byWidth.width == 3_600_000 && byWidth.height == 3_600_000)

        let byHeight = try NativeAspect.fittedSize(keeping: .height, of: Size(width: 1, height: 2_700_000),
                                                   pixelWidth: 1600, pixelHeight: 1200, crop: crop)
        #expect(byHeight.width == 2_700_000 && byHeight.height == 2_700_000)
    }

    @Test func `A negative crop extends the visible area`() throws {
        // bottom −50 %: 1600 × 1800 shown.
        let fitted = try NativeAspect.fittedSize(keeping: .width, of: Size(width: 3_600_000, height: 1),
                                                 pixelWidth: 1600, pixelHeight: 1200,
                                                 crop: PictureSourceRect(bottom: -50_000))
        #expect(fitted.height == 4_050_000)
    }

    @Test func `No crop and an all-zero crop give the uncropped aspect`() throws {
        let size = Size(width: 3_600_000, height: 1)
        let plain = try NativeAspect.fittedSize(keeping: .width, of: size, pixelWidth: 1600, pixelHeight: 1200)
        let zero = try NativeAspect.fittedSize(keeping: .width, of: size, pixelWidth: 1600, pixelHeight: 1200,
                                               crop: PictureSourceRect())
        #expect(plain.height == 2_700_000)
        #expect(zero.width == plain.width && zero.height == plain.height)
    }

    static let emptyCrops: [PictureSourceRect] = [
        PictureSourceRect(left: 60_000, right: 40_000),
        PictureSourceRect(left: 70_000, right: 70_000),
        PictureSourceRect(top: 100_000),
        PictureSourceRect(top: 50_000, bottom: 60_000),
    ]

    @Test(arguments: emptyCrops)
    func `A crop that leaves nothing visible is an error, not a zero or negative size`(crop: PictureSourceRect) {
        let error = #expect(throws: PPTXError.self) {
            _ = try NativeAspect.fittedSize(keeping: .width, of: Size(width: 3_600_000, height: 1),
                                            pixelWidth: 1600, pixelHeight: 1200, crop: crop)
        }
        guard case .invalidParameter(let name, _)? = error else {
            Issue.record("expected .invalidParameter, got \(String(describing: error))")
            return
        }
        #expect(name == "srcRect")
    }

    static let unrepresentableCrops: [PictureSourceRect] = [
        // The visible fraction is 0.5, but the edges do not fit xsd:int.
        PictureSourceRect(left: 3_000_000_000, right: -2_999_950_000),
        PictureSourceRect(top: Int(Int32.max) + 1),
        PictureSourceRect(bottom: Int(Int32.min) - 1),
        PictureSourceRect(left: .max),
        PictureSourceRect(right: .min),
    ]

    @Test(arguments: unrepresentableCrops)
    func `Crop edges outside the 32-bit range are rejected by fitting and by the writer`(crop: PictureSourceRect) {
        #expect(!crop.isRepresentable)
        let fitError = #expect(throws: PPTXError.self) {
            _ = try NativeAspect.fittedSize(keeping: .width, of: Size(width: 3_600_000, height: 1),
                                            pixelWidth: 1600, pixelHeight: 1200, crop: crop)
        }
        if case .invalidParameter(let name, _)? = fitError {
            #expect(name == "srcRect")
        } else {
            Issue.record("expected .invalidParameter, got \(String(describing: fitError))")
        }

        var pres = PptxWriter.createNew()
        pres.slides[0].elements = [.picture(Picture(id: 2, sourceRect: crop))]
        let url = TemporaryPPTX.url("badcrop")
        defer { try? FileManager.default.removeItem(at: url) }
        let writeError = #expect(throws: PPTXError.self) {
            try PptxWriter.write(pres, to: url)
        }
        if case .writeError(let message)? = writeError {
            #expect(message.contains("srcRect"))
        } else {
            Issue.record("expected .writeError, got \(String(describing: writeError))")
        }
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    @Test func `Crop edges at the 32-bit limits are written and read back exactly`() throws {
        let crop = PictureSourceRect(left: Int(Int32.max), top: Int(Int32.min), right: -1, bottom: 1)
        #expect(crop.isRepresentable)
        var pres = PptxWriter.createNew()
        pres.slides[0].elements = [.picture(Picture(id: 2, sourceRect: crop))]
        try TemporaryPPTX.written(pres) { url in
            let reread = try PptxReader.read(from: url)
            #expect(reread.slides[0].pictures.first?.sourceRect == crop)
        }
    }

    static let invalidPixelSizes: [(width: Int, height: Int)] = [(0, 100), (100, 0), (-1, 100), (100, -5)]

    @Test(arguments: invalidPixelSizes)
    func `Visible dimensions reject non-positive pixel sizes with or without a crop`(size: (width: Int, height: Int)) {
        for crop in [nil, PictureSourceRect(), PictureSourceRect(left: 10_000)] as [PictureSourceRect?] {
            let error = #expect(throws: PPTXError.self) {
                _ = try NativeAspect.visibleDimensions(pixelWidth: size.width, pixelHeight: size.height, crop: crop)
            }
            if case .invalidParameter(let name, _)? = error {
                #expect(name == "pixelDimensions")
            } else {
                Issue.record("expected .invalidParameter, got \(String(describing: error))")
            }
        }
    }

    @Test func `Orientation is applied before the crop`() throws {
        // Stored 1600 × 1200, shown 1200 × 1600; 25 % off left and right of
        // the upright image leaves 600 × 1600.
        let jpeg = try GeneratedImage.jpeg(width: 1600, height: 1200, orientation: 6)
        let dims = try NativeAspect.pixelDimensions(of: jpeg)
        let fitted = try NativeAspect.fittedSize(keeping: .width, of: Size(width: 600_000, height: 1),
                                                 pixelWidth: dims.width, pixelHeight: dims.height,
                                                 crop: PictureSourceRect(left: 25_000, right: 25_000))
        #expect(fitted.height == 1_600_000)
    }

    @Test func `A cropped picture from cropped.pptx fits to its visible pixels`() throws {
        let url = try #require(RealFileTests.fixturePath("cropped.pptx"))
        let pres = try PptxReader.read(from: url)
        let picture = try #require(pres.slides.flatMap(\.pictures).first { $0.id == 10 })
        let media = try #require(pres.mediaFile(for: picture))
        let dims = try NativeAspect.pixelDimensions(of: media.data)

        let fitted = try NativeAspect.fittedSize(keeping: .width, of: picture.size,
                                                 pixelWidth: dims.width, pixelHeight: dims.height,
                                                 crop: picture.sourceRect)
        let visibleWidth = Double(dims.width) * Double(100_000 - 2_878 - 21_582)
        let visibleHeight = Double(dims.height) * Double(100_000 - 2_522 - 46_217)
        let expected = Int((Double(picture.size.width) * visibleHeight / visibleWidth).rounded())
        #expect(fitted.width == picture.size.width)
        #expect(abs(fitted.height - expected) <= 1, "fitted \(fitted.height), expected \(expected)")

        let uncropped = try NativeAspect.fittedSize(keeping: .width, of: picture.size,
                                                    pixelWidth: dims.width, pixelHeight: dims.height)
        #expect(uncropped.height != fitted.height, "the crop must change the fitted height")
    }

    // MARK: - Writer keeps the crop

    @Test func `srcRect survives a write and read round trip`() throws {
        let url = try #require(RealFileTests.fixturePath("cropped.pptx"))
        let original = try PptxReader.read(from: url)
        try TemporaryPPTX.written(original, "crop") { written in
            let reread = try PptxReader.read(from: written)
            let before = Dictionary(uniqueKeysWithValues: original.slides.flatMap(\.pictures).map { ($0.id, $0.sourceRect) })
            let after = Dictionary(uniqueKeysWithValues: reread.slides.flatMap(\.pictures).map { ($0.id, $0.sourceRect) })
            #expect(after.count == before.count)
            for (id, rect) in before {
                #expect(after[id] == .some(rect), "picture \(id)")
            }
        }
    }

    @Test func `The writer places srcRect between the blip and the fill mode`() throws {
        var pres = PptxWriter.createNew()
        let png = try GeneratedImage.png(width: 16, height: 12)
        pres.images = [MediaFile(id: "c.png", fileName: "c.png", data: png)]
        pres.slides[0].elements = [.picture(Picture(
            id: 2, name: "Cropped", size: Size(width: 914400, height: 914400),
            mediaFileName: "c.png", sourceRect: PictureSourceRect(left: 10_000, bottom: -5_000)
        ))]
        try TemporaryPPTX.written(pres) { url in
            let package = try PackageInspector(url)
            defer { package.cleanup() }
            let blipFill = try #require(
                try package.xml("ppt/slides/slide1.xml").nodes(forXPath: "//*[local-name()='blipFill']").first as? XMLElement
            )
            let children = (blipFill.children ?? []).compactMap { ($0 as? XMLElement)?.localName }
            #expect(children == ["blip", "srcRect", "stretch"])
            let srcRect = try #require(blipFill.elements(forName: "a:srcRect").first)
            #expect(srcRect.attribute(forName: "l")?.stringValue == "10000")
            #expect(srcRect.attribute(forName: "b")?.stringValue == "-5000")
            #expect(srcRect.attribute(forName: "t") == nil, "zero edges are omitted")
            #expect(srcRect.attribute(forName: "r") == nil)
        }
    }
}

extension GeneratedImage {
    /// A small solid image encoded as `type` (GIF, BMP, TIFF, …).
    static func encoded(_ type: UTType, width: Int = 8, height: Int = 6) throws -> Data {
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { throw GenerationFailed() }
        context.setFillColor(red: 0.1, green: 0.6, blue: 0.3, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        guard let image = context.makeImage() else { throw GenerationFailed() }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, type.identifier as CFString, 1, nil)
        else { throw GenerationFailed() }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw GenerationFailed() }
        return output as Data
    }

    /// A JPEG whose stored pixel grid is `width` × `height`, tagged with the
    /// given EXIF orientation (1–8).
    static func jpeg(width: Int, height: Int, orientation: Int) throws -> Data {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { throw GenerationFailed() }
        context.setFillColor(red: 0.8, green: 0.3, blue: 0.2, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        guard let image = context.makeImage() else { throw GenerationFailed() }

        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output, UTType.jpeg.identifier as CFString, 1, nil
        ) else { throw GenerationFailed() }
        let properties = [kCGImagePropertyOrientation: orientation] as CFDictionary
        CGImageDestinationAddImage(destination, image, properties)
        guard CGImageDestinationFinalize(destination) else { throw GenerationFailed() }
        return output as Data
    }
}

extension PictureMediaTests {
    /// cropped.pptx with literal substitutions applied to `ppt/slides/slide1.xml`.
    static func tamperedSlide(replacing substitutions: [(String, String)]) throws -> URL {
        let fixture = try #require(RealFileTests.fixturePath("cropped.pptx"))
        let dir = try ZipHelper.unzip(fixture)
        defer { ZipHelper.cleanup(dir) }
        let slideURL = dir.appendingPathComponent("ppt/slides/slide1.xml")
        var xml = try String(contentsOf: slideURL, encoding: .utf8)
        for (from, to) in substitutions {
            #expect(xml.contains(from), "fixture no longer contains \(from)")
            xml = xml.replacingOccurrences(of: from, with: to)
        }
        try xml.write(to: slideURL, atomically: true, encoding: .utf8)
        let out = FileManager.default.temporaryDirectory
            .appendingPathComponent("pptx-slide-\(UUID().uuidString).pptx")
        try ZipHelper.zip(dir, to: out)
        return out
    }
}
