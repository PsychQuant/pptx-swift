import Testing
import Foundation
import OOXMLSwift
@testable import PPTXSwift

/// A picture's `r:embed` relationship resolved to its media part, so native
/// aspect can be read for pictures in opened decks (not only ones inserted
/// in-session). Prerequisite for `fit_picture_to_native_aspect`
/// (spec `pptx-mcp-server`, PsychQuant/macdoc#90).
struct PictureMediaTests {

    @Test func `Reader resolves each picture's embed to its media file name`() throws {
        let url = try #require(RealFileTests.fixturePath("cropped.pptx"))
        let pres = try PptxReader.read(from: url)
        let pictures = pres.slides.flatMap(\.pictures)
        #expect(!pictures.isEmpty)
        for picture in pictures {
            #expect(picture.imageRelationshipId == "rId2")
            #expect(picture.mediaFileName == "image1.png")
        }
    }

    @Test func `Presentation returns the media bytes behind a picture`() throws {
        let url = try #require(RealFileTests.fixturePath("cropped.pptx"))
        let pres = try PptxReader.read(from: url)
        let picture = try #require(pres.slides.flatMap(\.pictures).first)

        let media = try #require(pres.mediaFile(for: picture))
        #expect(media.fileName == "image1.png")
        let pixels = try NativeAspect.pixelDimensions(of: media.data)
        #expect(pixels.width > 0 && pixels.height > 0)
    }

    // MARK: - Relationship target resolution (review MEDIUM 1)

    /// cropped.pptx with its single image relationship (rId2, `../media/image1.png`)
    /// rewritten, and optional extra files dropped into the package.
    static func tamperedCropped(
        relationship: String?, extraFiles: [String: Data] = [:], renames: [String: String] = [:],
        contentTypeOverrides: [String: String] = [:]
    ) throws -> URL {
        let fixture = try #require(RealFileTests.fixturePath("cropped.pptx"))
        let dir = try ZipHelper.unzip(fixture)
        defer { ZipHelper.cleanup(dir) }

        let relsURL = dir.appendingPathComponent("ppt/slides/_rels/slide1.xml.rels")
        var rels = try String(contentsOf: relsURL, encoding: .utf8)
        let original = #"<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" Target="../media/image1.png"/>"#
        #expect(rels.contains(original))
        rels = rels.replacingOccurrences(of: original, with: relationship ?? "")
        try rels.write(to: relsURL, atomically: true, encoding: .utf8)

        for (from, to) in renames {
            try FileManager.default.moveItem(at: dir.appendingPathComponent(from), to: dir.appendingPathComponent(to))
        }
        for (path, data) in extraFiles {
            let url = dir.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url)
        }
        if !contentTypeOverrides.isEmpty {
            let typesURL = dir.appendingPathComponent("[Content_Types].xml")
            var types = try String(contentsOf: typesURL, encoding: .utf8)
            let overrides = contentTypeOverrides.map { #"<Override PartName="\#($0.key)" ContentType="\#($0.value)"/>"# }.joined()
            types = types.replacingOccurrences(of: "</Types>", with: overrides + "</Types>")
            try types.write(to: typesURL, atomically: true, encoding: .utf8)
        }
        let out = FileManager.default.temporaryDirectory
            .appendingPathComponent("pptx-media-\(UUID().uuidString).pptx")
        try ZipHelper.zip(dir, to: out)
        return out
    }

    static func imageRel(target: String, mode: String? = nil) -> String {
        let modeAttr = mode.map { #" TargetMode="\#($0)""# } ?? ""
        return #"<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" Target="\#(target)"\#(modeAttr)/>"#
    }

    static func mediaNames(of url: URL) throws -> [String?] {
        defer { try? FileManager.default.removeItem(at: url) }
        let pres = try PptxReader.read(from: url)
        let pictures = pres.slides.flatMap(\.pictures)
        #expect(!pictures.isEmpty)
        return pictures.map(\.mediaFileName)
    }

    @Test func `A target escaping ppt/media is not resolved even when a same-named media exists`() throws {
        let url = try Self.tamperedCropped(
            relationship: Self.imageRel(target: "../../outside/image1.png"),
            extraFiles: ["outside/image1.png": Data([0x01, 0x02])]
        )
        #expect(try Self.mediaNames(of: url).allSatisfy { $0 == nil })
    }

    @Test(arguments: ["https://example.com/image1.png", "../media/image1.png"])
    func `External relationships are never resolved`(target: String) throws {
        let url = try Self.tamperedCropped(relationship: Self.imageRel(target: target, mode: "External"))
        #expect(try Self.mediaNames(of: url).allSatisfy { $0 == nil })
    }

    @Test func `A missing relationship leaves the media name nil`() throws {
        let url = try Self.tamperedCropped(relationship: nil)
        #expect(try Self.mediaNames(of: url).allSatisfy { $0 == nil })
    }

    @Test func `A relationship to a media part that does not exist is not resolved`() throws {
        let url = try Self.tamperedCropped(relationship: Self.imageRel(target: "../media/missing.png"))
        #expect(try Self.mediaNames(of: url).allSatisfy { $0 == nil })
    }

    @Test func `A media file nested below ppt/media is not resolved`() throws {
        let url = try Self.tamperedCropped(
            relationship: Self.imageRel(target: "../media/sub/image1.png"),
            extraFiles: ["ppt/media/sub/image1.png": Data([0x01])]
        )
        #expect(try Self.mediaNames(of: url).allSatisfy { $0 == nil })
    }

    @Test(arguments: ["../media/image1.png", "/ppt/media/image1.png", "./../media/./image1.png", "../slides/../media/image1.png"])
    func `Equivalent targets for ppt/media/image1.png all resolve`(target: String) throws {
        let url = try Self.tamperedCropped(relationship: Self.imageRel(target: target))
        #expect(try Self.mediaNames(of: url).allSatisfy { $0 == "image1.png" })
    }

    @Test func `A percent-encoded target resolves to the decoded media file name end to end`() throws {
        let url = try Self.tamperedCropped(
            relationship: Self.imageRel(target: "../media/image%201.png"),
            renames: ["ppt/media/image1.png": "ppt/media/image 1.png"]
        )
        defer { try? FileManager.default.removeItem(at: url) }

        let pres = try PptxReader.read(from: url)
        #expect(pres.images.map(\.fileName) == ["image 1.png"])
        let pictures = pres.slides.flatMap(\.pictures)
        #expect(!pictures.isEmpty)
        for picture in pictures {
            #expect(picture.mediaFileName == "image 1.png")
            let media = try #require(pres.mediaFile(for: picture))
            #expect(media.fileName == "image 1.png")
            let pixels = try NativeAspect.pixelDimensions(of: media.data)
            #expect(pixels.width > 0 && pixels.height > 0)
        }
    }

    static let partResolutionCases: [(target: String, source: String, expected: String?)] = [
        ("../media/image1.png", "ppt/slides/slide1.xml", "ppt/media/image1.png"),
        ("/ppt/media/image1.png", "ppt/slides/slide1.xml", "ppt/media/image1.png"),
        ("media/image1.png", "ppt/slides/slide1.xml", "ppt/slides/media/image1.png"),
        ("../../outside/image1.png", "ppt/slides/slide1.xml", "outside/image1.png"),
        ("../../../escape.png", "ppt/slides/slide1.xml", nil),
        ("../media/image%201.png", "ppt/slides/slide1.xml", "ppt/media/image 1.png"),
        ("slides/slide1.xml", "ppt/presentation.xml", "ppt/slides/slide1.xml"),
        ("", "ppt/slides/slide1.xml", nil),
    ]

    @Test(arguments: partResolutionCases)
    func `Part names resolve relative to the source part and normalise dot segments`(
        c: (target: String, source: String, expected: String?)
    ) {
        #expect(PptxReader.resolvePartPath(target: c.target, relativeTo: c.source) == c.expected)
    }

    @Test func `In-memory pictures resolve by media file name, absent names do not`() {
        var pres = Presentation()
        pres.images = [MediaFile(id: "a.png", fileName: "a.png", data: Data([1, 2, 3]))]

        let linked = Picture(id: 2, name: "A", imageRelationshipId: "rId2", mediaFileName: "a.png")
        #expect(pres.mediaFile(for: linked)?.data == Data([1, 2, 3]))

        let unlinked = Picture(id: 3, name: "a.png", imageRelationshipId: "rId3")
        #expect(pres.mediaFile(for: unlinked) == nil)

        let dangling = Picture(id: 4, name: "B", imageRelationshipId: "rId4", mediaFileName: "missing.png")
        #expect(pres.mediaFile(for: dangling) == nil)
    }
}
