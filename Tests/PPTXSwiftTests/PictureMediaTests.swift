import Testing
import Foundation
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
