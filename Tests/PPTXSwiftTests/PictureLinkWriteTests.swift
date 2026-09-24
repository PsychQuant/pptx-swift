import Testing
import Foundation
import OOXMLSwift
@testable import PPTXSwift

/// PsychQuant/pptx-swift#5 (secondary): an externally-linked picture
/// (`<a:blip r:link="...">`, `TargetMode="External"` — no embedded media
/// bytes) is modeled rather than silently dropped: `Picture.externalImageTarget`
/// round-trips through `PptxWriter`/`PptxReader`.
struct PictureLinkWriteTests {

    @Test func `A picture linking an external image round-trips without embedding media`() throws {
        var pres = PptxWriter.createNew()
        pres.slides[0].elements = [
            .picture(Picture(id: 2, name: "Linked photo",
                              position: Position(x: 914400, y: 914400), size: Size(width: 1828800, height: 1371600),
                              externalImageTarget: "https://example.com/photo.png")),
        ]

        try TemporaryPPTX.written(pres) { url in
            let package = try PackageInspector(url)
            defer { package.cleanup() }
            let violations = try package.integrityViolations()
            #expect(violations == [])

            // No r:embed at all; r:link resolves to an External relationship
            // whose Target is the raw link string, unresolved (it never
            // names a package part).
            #expect(try package.blipEmbeds(in: "ppt/slides/slide1.xml") == [nil])
            let link = try #require(try package.blipLinks(in: "ppt/slides/slide1.xml").first ?? nil)
            let rel = try #require(try package.relationships(of: "ppt/slides/slide1.xml").first { $0.id == link })
            #expect(rel.type == PackageInspector.imageRelType)
            #expect(rel.isExternal)
            #expect(rel.target == "https://example.com/photo.png")

            // No media part was written for a link-only picture.
            #expect(try package.partNames().filter { $0.hasPrefix("ppt/media/") } == [])

            let reread = try PptxReader.read(from: url)
            let picture = try #require(reread.slides[0].pictures.first)
            #expect(picture.externalImageTarget == "https://example.com/photo.png")
            #expect(picture.mediaFileName == nil)
        }
    }

    @Test func `Pictures linking the same external target share one relationship`() throws {
        var pres = PptxWriter.createNew()
        pres.slides[0].elements = [
            .picture(Picture(id: 2, externalImageTarget: "https://example.com/shared.png")),
            .picture(Picture(id: 3, externalImageTarget: "https://example.com/shared.png")),
        ]

        try TemporaryPPTX.written(pres) { url in
            let package = try PackageInspector(url)
            defer { package.cleanup() }
            #expect(try package.integrityViolations() == [])

            let links = try package.blipLinks(in: "ppt/slides/slide1.xml").compactMap { $0 }
            #expect(links.count == 2)
            #expect(Set(links).count == 1, "both pictures should reuse the same relationship Id")
        }
    }

    @Test func `An embedded picture never also carries r:link`() throws {
        // mediaFileName takes priority over externalImageTarget when (unusually)
        // both are set — a blip is one or the other, never both.
        let png = try GeneratedImage.png(width: 4, height: 4)
        var pres = PptxWriter.createNew()
        pres.images = [MediaFile(id: "p.png", fileName: "p.png", data: png)]
        pres.slides[0].elements = [
            .picture(Picture(id: 2, mediaFileName: "p.png", externalImageTarget: "https://example.com/ignored.png")),
        ]

        try TemporaryPPTX.written(pres) { url in
            let package = try PackageInspector(url)
            defer { package.cleanup() }
            #expect(try package.integrityViolations() == [])
            #expect(try package.blipLinks(in: "ppt/slides/slide1.xml") == [nil])
            #expect(try package.blipEmbeds(in: "ppt/slides/slide1.xml").first ?? nil != nil)
        }
    }
}
