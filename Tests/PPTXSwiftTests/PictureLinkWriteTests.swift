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

    @Test func `A picture with both an embedded cache and an external link round-trips both`() throws {
        // CT_Blip's r:embed and r:link are independent optional attributes
        // (ECMA-376 Part 1 §20.1.8.13), not alternatives: PowerPoint's
        // "Insert and Link" produces exactly this — an embedded cached copy
        // plus a link back to the original file. Dropping either on write
        // would silently lose content (Codex review round 1, HIGH 1).
        let png = try GeneratedImage.png(width: 4, height: 4)
        var pres = PptxWriter.createNew()
        pres.images = [MediaFile(id: "p.png", fileName: "p.png", data: png)]
        pres.slides[0].elements = [
            .picture(Picture(id: 2, mediaFileName: "p.png", externalImageTarget: "https://example.com/original.png")),
        ]

        try TemporaryPPTX.written(pres) { url in
            let package = try PackageInspector(url)
            defer { package.cleanup() }
            #expect(try package.integrityViolations() == [])

            let embed = try #require(try package.blipEmbeds(in: "ppt/slides/slide1.xml").first ?? nil)
            let link = try #require(try package.blipLinks(in: "ppt/slides/slide1.xml").first ?? nil)
            #expect(embed != link, "embed and link must be distinct relationships")

            let embedRel = try #require(try package.relationships(of: "ppt/slides/slide1.xml").first { $0.id == embed })
            #expect(!embedRel.isExternal)
            #expect(package.resolve(embedRel, from: "ppt/slides/slide1.xml") == "ppt/media/p.png")

            let linkRel = try #require(try package.relationships(of: "ppt/slides/slide1.xml").first { $0.id == link })
            #expect(linkRel.isExternal)
            #expect(linkRel.target == "https://example.com/original.png")

            let reread = try PptxReader.read(from: url)
            let picture = try #require(reread.slides[0].pictures.first)
            #expect(reread.mediaFile(for: picture)?.data == png)
            #expect(picture.externalImageTarget == "https://example.com/original.png")
        }
    }
}
